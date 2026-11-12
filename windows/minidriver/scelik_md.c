/*
 * Super Celik: Windows smart card minidriver for the NetSeT CardEdge applet (PKCS#15 AID A000000063504B43532D3135)
 * found on Serbian ID cards, foreigner ID cards, residence permits and CardEdge USB tokens.
 *
 * Why it exists: Chrome and Edge on Windows take TLS client certificates from the Windows certificate store, and a
 * smart card shows up there only through a card minidriver (the "Microsoft Base Smart Card Crypto Provider" calls it).
 * Without one the card is invisible to the browser ("no certificate" on eid.gov.rs) even though Super Celik reads it.
 * This is the Windows counterpart of the macOS CryptoTokenKit extension (TokenExtension/TokenDriver.swift) and speaks
 * the same card protocol.
 *
 * The driver is registered for a card's ATR by Super Celik itself (elevated, once; see DriverSetup.cs). On
 * CardAcquireContext it checks that the CardEdge applet answers, so a card with the same ATR but another applet
 * is declined (SCARD_E_UNKNOWN_CARD).
 *
 * Card layout (same as TokenDriver.swift):
 *   8FFF = index: [count LE16] + count * [file id LE16] of meta files
 *   meta file = [class][file id BE16][label len][label][id len = 20][id]     class 1 = certificate, 2 = public key
 *   certificate file = [len LE16][01 00][uncompressed size LE16][zlib stream]
 *       -> after the 2-byte length it is exactly Microsoft's "compressed certificate" format, passed through as is
 *   public key file  = 00 05 xx <private key file BE16> <modulus len BE16> <modulus> <exp len BE16> <exp>
 * Signing: MSE SET 00 22 41 B6 [80 01 alg][84 02 key file], then PSO 00 2A 9E P2 <data> Le=00.
 *   alg 2 = the card adds PKCS#1 v1.5 padding to a DigestInfo; alg 0 = raw RSA, the first byte of the
 *   256-byte block goes into P2 (that is how a full block fits a short APDU).
 * PIN: VERIFY 00 20 00 80 08 <ASCII digits, 0x00-padded to 8>; 63Cx = x tries left.
 *
 * Debug log: set HKLM\SOFTWARE\SuperCelik\MinidriverLog (DWORD) = 1, the log goes to
 * %ProgramData%\SuperCelik\minidriver.log. HKLM\SOFTWARE\SuperCelik\SigBigEndian = 1 returns signatures big-endian
 * (default: little-endian, the CryptoAPI order).
 */
#define WIN32_LEAN_AND_MEAN
#define WIN32_NO_STATUS
#include <windows.h>
#include <winscard.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "cardmod.h"

#ifndef NT_SUCCESS
#define NT_SUCCESS(s) ((s) >= 0)
#endif

#define MAX_PAIRS 4
#define BIT_ATTEMPT_UNKNOWN 0xFFFFFFFF

static const BYTE kAid[] = { 0xA0, 0x00, 0x00, 0x00, 0x63, 0x50, 0x4B, 0x43, 0x53, 0x2D, 0x31, 0x35 };

typedef struct {
    WORD   keyFile;       /* private key file id */
    DWORD  bits;
    BYTE  *certFile;      /* the card's certificate file without the 2-byte length prefix (MS compressed format) */
    DWORD  certLen;
    BYTE  *blob;          /* CryptoAPI PUBLICKEYBLOB */
    DWORD  blobLen;
    WCHAR  guid[40];
} Pair;

typedef struct {
    int    loaded;
    int    nPairs;
    Pair   pairs[MAX_PAIRS];
    BYTE   cardId[16];
    DWORD  authenticated;     /* PIN_SET bits */
    const SCARD_IO_REQUEST *pci;
} MD;

/* ---------------------------------------------------------------- logging */

static int g_logOn = -1;
static int g_beSig = -1;
static int g_revHash = -1;   /* legacy CryptoAPI path only: HKLM\SOFTWARE\SuperCelik\ReverseHashInput = 1 */

static DWORD regDword(const wchar_t *name, DWORD def)
{
    HKEY k; DWORD v = def, n = sizeof v, t = 0;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\SuperCelik", 0, KEY_READ | KEY_WOW64_64KEY, &k) == ERROR_SUCCESS) {
        if (RegQueryValueExW(k, name, NULL, &t, (BYTE *)&v, &n) != ERROR_SUCCESS || t != REG_DWORD) v = def;
        RegCloseKey(k);
    }
    return v;
}

static void logf_(const char *fmt, ...)
{
    char line[512], path[MAX_PATH]; va_list ap; FILE *f; DWORD n; SYSTEMTIME st;
    if (g_logOn < 0) g_logOn = regDword(L"MinidriverLog", 0) ? 1 : 0;
    if (!g_logOn) return;
    n = GetEnvironmentVariableA("ProgramData", path, sizeof path - 32);
    if (n == 0 || n > sizeof path - 32) return;
    strcat(path, "\\SuperCelik"); CreateDirectoryA(path, NULL);
    strcat(path, "\\minidriver.log");
    va_start(ap, fmt); _vsnprintf(line, sizeof line - 1, fmt, ap); va_end(ap);
    line[sizeof line - 1] = 0;
    f = fopen(path, "a"); if (!f) return;
    GetLocalTime(&st);
    fprintf(f, "%02d:%02d:%02d.%03d [%lu] %s\n", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, GetCurrentProcessId(), line);
    fclose(f);
}
#define LOG logf_

/* ---------------------------------------------------------------- card I/O */

static MD *md(PCARD_DATA cd) { return (MD *)cd->pvVendorSpecific; }

/* One APDU with 61xx / 6Cxx handling. out may be NULL. */
static LONG apdu(PCARD_DATA cd, const BYTE *cmd, DWORD cmdLen, BYTE *out, DWORD outCap, DWORD *outLen, WORD *sw)
{
    BYTE resp[600]; DWORD rl; LONG rc; BYTE again[300]; DWORD total = 0;
    MD *m = md(cd);
    if (outLen) *outLen = 0;
    rl = sizeof resp;
    rc = SCardTransmit(cd->hScard, m->pci, cmd, cmdLen, NULL, resp, &rl);
    if (rc != SCARD_S_SUCCESS) { LOG("SCardTransmit failed %08lX", (unsigned long)rc); return rc; }
    if (rl < 2) return SCARD_E_UNEXPECTED;
    if (resp[rl - 2] == 0x6C && cmdLen >= 5 && cmdLen <= sizeof again) {
        memcpy(again, cmd, cmdLen); again[cmdLen - 1] = resp[rl - 1];
        rl = sizeof resp;
        rc = SCardTransmit(cd->hScard, m->pci, again, cmdLen, NULL, resp, &rl);
        if (rc != SCARD_S_SUCCESS) return rc;
        if (rl < 2) return SCARD_E_UNEXPECTED;
    }
    for (;;) {
        DWORD dl = rl - 2;
        if (out && total + dl <= outCap) { memcpy(out + total, resp, dl); }
        else if (dl && out) return SCARD_E_INSUFFICIENT_BUFFER;
        total += dl;
        if (resp[rl - 2] == 0x61) {
            BYTE gr[5] = { 0x00, 0xC0, 0x00, 0x00, resp[rl - 1] };
            rl = sizeof resp;
            rc = SCardTransmit(cd->hScard, m->pci, gr, 5, NULL, resp, &rl);
            if (rc != SCARD_S_SUCCESS) return rc;
            if (rl < 2) return SCARD_E_UNEXPECTED;
            continue;
        }
        break;
    }
    if (outLen) *outLen = total;
    *sw = (WORD)(resp[rl - 2] << 8 | resp[rl - 1]);
    return SCARD_S_SUCCESS;
}

static LONG selectApplet(PCARD_DATA cd)
{
    BYTE cmd[5 + sizeof kAid] = { 0x00, 0xA4, 0x04, 0x00, sizeof kAid }; WORD sw = 0; LONG rc;
    memcpy(cmd + 5, kAid, sizeof kAid);
    rc = apdu(cd, cmd, sizeof cmd, NULL, 0, NULL, &sw);
    if (rc != SCARD_S_SUCCESS) return rc;
    if (sw != 0x9000) { LOG("SELECT applet: %04X", sw); return SCARD_E_UNKNOWN_CARD; }
    return SCARD_S_SUCCESS;
}

/* SELECT by file id; file size is bytes 2-3 (BE) of the FCI; then READ BINARY in chunks. Caller frees with LocalFree. */
static LONG readFile(PCARD_DATA cd, WORD fid, BYTE **data, DWORD *len)
{
    BYTE sel[7] = { 0x00, 0xA4, 0x00, 0x00, 0x02, (BYTE)(fid >> 8), (BYTE)fid }, fci[64]; DWORD fl; WORD sw = 0; LONG rc;
    DWORD size, got = 0; BYTE *buf;
    rc = apdu(cd, sel, sizeof sel, fci, sizeof fci, &fl, &sw);
    if (rc != SCARD_S_SUCCESS) return rc;
    if (sw != 0x9000 || fl < 4) { LOG("select file %04X: %04X", fid, sw); return SCARD_E_FILE_NOT_FOUND; }
    size = (DWORD)fci[2] << 8 | fci[3];
    buf = (BYTE *)LocalAlloc(LPTR, size ? size : 1);
    if (!buf) return SCARD_E_NO_MEMORY;
    while (got < size) {
        DWORD n = size - got > 0xE0 ? 0xE0 : size - got, rl = 0;
        BYTE rd[5] = { 0x00, 0xB0, (BYTE)(got >> 8), (BYTE)got, (BYTE)n };
        rc = apdu(cd, rd, 5, buf + got, size - got, &rl, &sw);
        if (rc != SCARD_S_SUCCESS || sw != 0x9000 || rl == 0) { LocalFree(buf); return rc != SCARD_S_SUCCESS ? rc : SCARD_E_UNEXPECTED; }
        got += rl;
    }
    *data = buf; *len = size;
    return SCARD_S_SUCCESS;
}

/* ---------------------------------------------------------------- reading the card's objects */

typedef struct { BYTE cls; WORD fid; BYTE id[20]; int hasId; } Meta;

static void makeGuid(MD *m, int i, WORD keyFile)
{
    swprintf(m->pairs[i].guid, 40, L"{%08X-%04X-%04X-%04X-%02X%02X%02X%02X%02X%02X}",
             *(DWORD *)m->cardId, keyFile, (unsigned)(i + 1), *(WORD *)(m->cardId + 4),
             m->cardId[6], m->cardId[7], m->cardId[8], m->cardId[9], m->cardId[10], m->cardId[11]);
}

static LONG loadObjects(PCARD_DATA cd, MD *m)
{
    BYTE *idx = NULL; DWORD il = 0; LONG rc; int count, i, nm = 0; Meta metas[32];
    if (m->loaded) return SCARD_S_SUCCESS;
    rc = selectApplet(cd); if (rc) return rc;
    rc = readFile(cd, 0x8FFF, &idx, &il); if (rc) return rc;
    if (il < 2) { LocalFree(idx); return SCARD_E_UNKNOWN_CARD; }
    count = idx[0] | idx[1] << 8;
    if (count > 32) count = 32;
    if (2 + 2 * (DWORD)count > il) { LocalFree(idx); return SCARD_E_UNKNOWN_CARD; }
    for (i = 0; i < count; i++) {
        WORD fid = (WORD)(idx[2 + 2 * i] | idx[3 + 2 * i] << 8); BYTE *f = NULL; DWORD fl = 0; DWORD p, labelLen, idLen;
        if (readFile(cd, fid, &f, &fl) != SCARD_S_SUCCESS) continue;
        if (fl >= 5 && f[0] >= 1 && f[0] <= 3) {
            labelLen = f[3]; p = 4 + labelLen;
            if (p < fl) {
                idLen = f[p]; p++;
                if (p + idLen <= fl && idLen == 20) {
                    Meta *mm = &metas[nm++];
                    mm->cls = f[0]; mm->fid = (WORD)(f[1] << 8 | f[2]); memcpy(mm->id, f + p, 20); mm->hasId = 1;
                }
            }
        }
        LocalFree(f);
    }
    LocalFree(idx);
    for (i = 0; i < nm && m->nPairs < MAX_PAIRS; i++) {
        int j; Meta *c = &metas[i]; BYTE *cert = NULL, *pk = NULL; DWORD cl = 0, pl = 0;
        DWORD modLen, expLen, bits; Pair *pr;
        if (c->cls != 1) continue;
        for (j = 0; j < nm; j++) if (metas[j].cls == 2 && !memcmp(metas[j].id, c->id, 20)) break;
        if (j == nm) continue;
        if (readFile(cd, c->fid, &cert, &cl) != SCARD_S_SUCCESS) continue;
        if (readFile(cd, metas[j].fid, &pk, &pl) != SCARD_S_SUCCESS) { LocalFree(cert); continue; }
        if (cl < 8 || pl < 9 || pk[0] != 0x00 || pk[1] != 0x05) { LocalFree(cert); LocalFree(pk); continue; }
        modLen = (DWORD)pk[5] << 8 | pk[6];
        if (modLen == 0 || 7 + modLen + 2 > pl) { LocalFree(cert); LocalFree(pk); continue; }
        expLen = (DWORD)pk[7 + modLen] << 8 | pk[8 + modLen];
        if (expLen == 0 || expLen > 4 || 9 + modLen + expLen > pl) { LocalFree(cert); LocalFree(pk); continue; }
        bits = modLen * 8;
        pr = &m->pairs[m->nPairs];
        pr->keyFile = (WORD)(pk[3] << 8 | pk[4]);
        pr->bits = bits;
        pr->certLen = cl - 2;
        pr->certFile = (BYTE *)LocalAlloc(LPTR, pr->certLen);
        pr->blobLen = sizeof(BLOBHEADER) + sizeof(RSAPUBKEY) + modLen;
        pr->blob = (BYTE *)LocalAlloc(LPTR, pr->blobLen);
        if (pr->certFile && pr->blob) {
            BLOBHEADER *bh = (BLOBHEADER *)pr->blob; RSAPUBKEY *rk = (RSAPUBKEY *)(pr->blob + sizeof(BLOBHEADER));
            BYTE *mod = pr->blob + sizeof(BLOBHEADER) + sizeof(RSAPUBKEY); DWORD e = 0, k;
            memcpy(pr->certFile, cert + 2, pr->certLen);
            bh->bType = PUBLICKEYBLOB; bh->bVersion = CUR_BLOB_VERSION; bh->reserved = 0; bh->aiKeyAlg = CALG_RSA_KEYX;
            for (k = 0; k < expLen; k++) e = e << 8 | pk[9 + modLen + k];
            rk->magic = 0x31415352; rk->bitlen = bits; rk->pubexp = e;
            for (k = 0; k < modLen; k++) mod[k] = pk[7 + modLen - 1 - k];   /* big-endian on the card -> little-endian blob */
            m->nPairs++;
            LOG("pair %d: cert file %04X (%lu bytes), key file %04X, %lu bits", m->nPairs - 1, c->fid, (unsigned long)pr->certLen, pr->keyFile, (unsigned long)bits);
        } else { if (pr->certFile) LocalFree(pr->certFile); if (pr->blob) LocalFree(pr->blob); }
        LocalFree(cert); LocalFree(pk);
    }
    if (m->nPairs == 0) return SCARD_E_UNKNOWN_CARD;
    /* card id: a hash of the first modulus (unique per card, stable) */
    {
        Pair *p0 = &m->pairs[0]; DWORD k, n = p0->blobLen - sizeof(BLOBHEADER) - sizeof(RSAPUBKEY);
        BYTE *mod = p0->blob + sizeof(BLOBHEADER) + sizeof(RSAPUBKEY); ULONGLONG h1 = 1469598103934665603ULL, h2 = 1099511628211ULL;
        for (k = 0; k < n; k++) { h1 = (h1 ^ mod[k]) * 1099511628211ULL; h2 = (h2 + mod[k]) * 6364136223846793005ULL + 1442695040888963407ULL; }
        memcpy(m->cardId, &h1, 8); memcpy(m->cardId + 8, &h2, 8);
    }
    for (i = 0; i < m->nPairs; i++) makeGuid(m, i, m->pairs[i].keyFile);
    m->loaded = 1;
    return SCARD_S_SUCCESS;
}

/* ---------------------------------------------------------------- helpers */

static PBYTE cspAlloc(PCARD_DATA cd, DWORD n) { return cd->pfnCspAlloc ? (PBYTE)cd->pfnCspAlloc(n) : NULL; }

static DWORD copyOut(PCARD_DATA cd, const BYTE *src, DWORD n, PBYTE *out, PDWORD outLen)
{
    PBYTE p = cspAlloc(cd, n ? n : 1);
    if (!p) return ERROR_NOT_ENOUGH_MEMORY;
    memcpy(p, src, n); *out = p; *outLen = n;
    return SCARD_S_SUCCESS;
}

static int sameName(const char *a, const char *b) { return a && b && _stricmp(a, b) == 0; }

/* PIN: VERIFY with an 8-byte block */
static DWORD verifyPin(PCARD_DATA cd, const BYTE *pin, DWORD cb, PDWORD attempts)
{
    BYTE cmd[13] = { 0x00, 0x20, 0x00, 0x80, 0x08, 0, 0, 0, 0, 0, 0, 0, 0 }; WORD sw = 0; LONG rc; DWORD i;
    if (attempts) *attempts = BIT_ATTEMPT_UNKNOWN;
    if (cb < 4 || cb > 8) return SCARD_W_WRONG_CHV;
    for (i = 0; i < cb; i++) { if (pin[i] < '0' || pin[i] > '9') return SCARD_W_WRONG_CHV; cmd[5 + i] = pin[i]; }
    rc = selectApplet(cd); if (rc) return rc;
    rc = apdu(cd, cmd, sizeof cmd, NULL, 0, NULL, &sw);
    if (rc != SCARD_S_SUCCESS) return rc;
    LOG("VERIFY: %04X", sw);
    if (sw == 0x9000) { md(cd)->authenticated |= (1u << ROLE_USER); return SCARD_S_SUCCESS; }
    if (sw == 0x6983 || sw == 0x63C0) { if (attempts) *attempts = 0; return SCARD_W_CHV_BLOCKED; }
    if ((sw & 0xFFF0) == 0x63C0) { if (attempts) *attempts = sw & 0xF; return SCARD_W_WRONG_CHV; }
    return SCARD_W_WRONG_CHV;
}

/* ---------------------------------------------------------------- the minidriver entry points */

static DWORD WINAPI MdDeleteContext(PCARD_DATA cd)
{
    MD *m = cd ? md(cd) : NULL; int i;
    LOG("CardDeleteContext");
    if (m) {
        for (i = 0; i < m->nPairs; i++) { if (m->pairs[i].certFile) LocalFree(m->pairs[i].certFile); if (m->pairs[i].blob) LocalFree(m->pairs[i].blob); }
        LocalFree(m); cd->pvVendorSpecific = NULL;
    }
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdQueryCapabilities(PCARD_DATA cd, PCARD_CAPABILITIES caps)
{
    (void)cd; LOG("CardQueryCapabilities");
    if (!caps) return ERROR_INVALID_PARAMETER;
    caps->dwVersion = CARD_CAPABILITIES_CURRENT_VERSION;
    caps->fCertificateCompression = TRUE;
    caps->fKeyGen = FALSE;
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdUnsupported(void) { return SCARD_E_UNSUPPORTED_FEATURE; }

static DWORD WINAPI MdDeleteContainer(PCARD_DATA cd, BYTE i, DWORD r) { (void)cd; (void)i; (void)r; return SCARD_E_UNSUPPORTED_FEATURE; }
static DWORD WINAPI MdCreateContainer(PCARD_DATA cd, BYTE i, DWORD f, DWORD ks, DWORD sz, PBYTE d) { (void)cd; (void)i; (void)f; (void)ks; (void)sz; (void)d; return SCARD_E_UNSUPPORTED_FEATURE; }

static DWORD WINAPI MdGetContainerInfo(PCARD_DATA cd, BYTE idx, DWORD flags, PCONTAINER_INFO info)
{
    MD *m = md(cd); DWORD rc;
    LOG("CardGetContainerInfo %u", idx);
    if (!info || flags != 0) return ERROR_INVALID_PARAMETER;
    if (idx >= m->nPairs) return SCARD_E_NO_KEY_CONTAINER;
    info->dwVersion = CONTAINER_INFO_CURRENT_VERSION;
    info->dwReserved = 0;
    info->cbSigPublicKey = 0; info->pbSigPublicKey = NULL;
    rc = copyOut(cd, m->pairs[idx].blob, m->pairs[idx].blobLen, &info->pbKeyExPublicKey, &info->cbKeyExPublicKey);
    return rc;
}

static DWORD WINAPI MdAuthenticatePin(PCARD_DATA cd, LPWSTR user, PBYTE pin, DWORD cb, PDWORD attempts)
{
    LOG("CardAuthenticatePin");
    if (!user || _wcsicmp(user, wszCARD_USER_USER) != 0) return SCARD_E_INVALID_PARAMETER;
    return verifyPin(cd, pin, cb, attempts);
}

static DWORD WINAPI MdAuthenticateEx(PCARD_DATA cd, PIN_ID pinId, DWORD flags, PBYTE pin, DWORD cb, PBYTE *session, PDWORD sessionLen, PDWORD attempts)
{
    LOG("CardAuthenticateEx pin %lu flags %08lX", (unsigned long)pinId, (unsigned long)flags);
    if (pinId != ROLE_USER) return SCARD_E_INVALID_PARAMETER;
    if (flags & (CARD_AUTHENTICATE_GENERATE_SESSION_PIN | CARD_AUTHENTICATE_SESSION_PIN)) return SCARD_E_UNSUPPORTED_FEATURE;
    if (session) *session = NULL;
    if (sessionLen) *sessionLen = 0;
    return verifyPin(cd, pin, cb, attempts);
}

static DWORD WINAPI MdDeauthenticate(PCARD_DATA cd, LPWSTR user, DWORD flags)
{
    (void)user; (void)flags; LOG("CardDeauthenticate");
    md(cd)->authenticated = 0;
    return SCARD_E_UNSUPPORTED_FEATURE;   /* the card cannot drop the PIN state without a reset */
}
static DWORD WINAPI MdDeauthenticateEx(PCARD_DATA cd, PIN_SET pins, DWORD flags)
{
    (void)pins; (void)flags; LOG("CardDeauthenticateEx");
    md(cd)->authenticated = 0;
    return SCARD_E_UNSUPPORTED_FEATURE;
}

static DWORD WINAPI MdCreateDirectory(PCARD_DATA cd, LPSTR d, CARD_DIRECTORY_ACCESS_CONDITION ac) { (void)cd; (void)d; (void)ac; return SCARD_E_UNSUPPORTED_FEATURE; }
static DWORD WINAPI MdDeleteDirectory(PCARD_DATA cd, LPSTR d) { (void)cd; (void)d; return SCARD_E_UNSUPPORTED_FEATURE; }
static DWORD WINAPI MdCreateFile(PCARD_DATA cd, LPSTR d, LPSTR f, DWORD n, CARD_FILE_ACCESS_CONDITION ac) { (void)cd; (void)d; (void)f; (void)n; (void)ac; return SCARD_E_UNSUPPORTED_FEATURE; }
static DWORD WINAPI MdWriteFile(PCARD_DATA cd, LPSTR d, LPSTR f, DWORD fl, PBYTE b, DWORD n) { (void)cd; (void)d; (void)f; (void)fl; (void)b; (void)n; return SCARD_E_UNSUPPORTED_FEATURE; }
static DWORD WINAPI MdDeleteFile(PCARD_DATA cd, LPSTR d, LPSTR f, DWORD fl) { (void)cd; (void)d; (void)f; (void)fl; return SCARD_E_UNSUPPORTED_FEATURE; }

/* The virtual file system the Base CSP expects: cardid, cardcf, cardapps, and the "mscp" directory with cmapfile, kxcNN. */
#pragma pack(push, 1)
typedef struct { WCHAR guid[40]; BYTE flags; BYTE reserved; WORD sigBits; WORD kxBits; } CmapRecord;
#pragma pack(pop)

static BYTE *buildFile(PCARD_DATA cd, const char *dir, const char *file, DWORD *len, int *needFree)
{
    MD *m = md(cd); *needFree = 0;
    if (!dir || !*dir) {
        if (sameName(file, "cardid")) { *len = 16; return m->cardId; }
        if (sameName(file, "cardcf")) { static BYTE cf[6] = { 1, 0, 0, 0, 0, 0 }; *len = 6; return cf; }
        if (sameName(file, "cardapps")) { static BYTE apps[8] = { 'm', 's', 'c', 'p', 0, 0, 0, 0 }; *len = 8; return apps; }
        return NULL;
    }
    if (sameName(dir, "mscp")) {
        if (sameName(file, "cmapfile")) {
            CmapRecord *r = (CmapRecord *)LocalAlloc(LPTR, sizeof(CmapRecord) * MAX_PAIRS); int i;
            if (!r) return NULL;
            for (i = 0; i < m->nPairs; i++) {
                wcsncpy(r[i].guid, m->pairs[i].guid, 39);
                r[i].flags = CONTAINER_MAP_VALID_CONTAINER | (i == 0 ? CONTAINER_MAP_DEFAULT_CONTAINER : 0);
                r[i].sigBits = 0; r[i].kxBits = (WORD)m->pairs[i].bits;
            }
            *len = sizeof(CmapRecord) * m->nPairs; *needFree = 1;
            return (BYTE *)r;
        }
        if (file && _strnicmp(file, "kxc0", 4) == 0 && file[4] >= '0' && file[4] <= '9' && file[5] == 0) {
            int i = file[4] - '0';
            if (i < m->nPairs) { *len = m->pairs[i].certLen; return m->pairs[i].certFile; }
        }
    }
    return NULL;
}

static DWORD WINAPI MdReadFile(PCARD_DATA cd, LPSTR dir, LPSTR file, DWORD flags, PBYTE *out, PDWORD outLen)
{
    DWORD len = 0; int nf = 0; BYTE *src; DWORD rc;
    LOG("CardReadFile %s/%s", dir ? dir : "", file ? file : "");
    (void)flags;
    if (!out || !outLen || !file) return ERROR_INVALID_PARAMETER;
    rc = loadObjects(cd, md(cd)); if (rc) return rc;
    src = buildFile(cd, dir, file, &len, &nf);
    if (!src) return SCARD_E_FILE_NOT_FOUND;
    rc = copyOut(cd, src, len, out, outLen);
    if (nf) LocalFree(src);
    return rc;
}

static DWORD WINAPI MdEnumFiles(PCARD_DATA cd, LPSTR dir, LPSTR *names, LPDWORD len, DWORD flags)
{
    char list[256]; int n = 0, i; MD *m = md(cd); PBYTE p;
    LOG("CardEnumFiles %s", dir ? dir : "(root)");
    (void)flags;
    if (!names || !len) return ERROR_INVALID_PARAMETER;
    if (loadObjects(cd, m) != SCARD_S_SUCCESS) return SCARD_E_UNKNOWN_CARD;
    memset(list, 0, sizeof list);
    if (!dir || !*dir) {
        const char *r[] = { "cardapps", "cardcf", "cardid" };
        for (i = 0; i < 3; i++) { strcpy(list + n, r[i]); n += (int)strlen(r[i]) + 1; }
    } else if (sameName(dir, "mscp")) {
        strcpy(list + n, "cmapfile"); n += 9;
        for (i = 0; i < m->nPairs; i++) { sprintf(list + n, "kxc%02d", i); n += 6; }
    } else return SCARD_E_DIR_NOT_FOUND;
    n += 1;   /* final NUL */
    p = cspAlloc(cd, n); if (!p) return ERROR_NOT_ENOUGH_MEMORY;
    memcpy(p, list, n); *names = (LPSTR)p; *len = n;
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdGetFileInfo(PCARD_DATA cd, LPSTR dir, LPSTR file, PCARD_FILE_INFO info)
{
    DWORD len = 0; int nf = 0; BYTE *src;
    LOG("CardGetFileInfo %s/%s", dir ? dir : "", file ? file : "");
    if (!info || !file) return ERROR_INVALID_PARAMETER;
    if (loadObjects(cd, md(cd)) != SCARD_S_SUCCESS) return SCARD_E_UNKNOWN_CARD;
    src = buildFile(cd, dir, file, &len, &nf);
    if (!src) return SCARD_E_FILE_NOT_FOUND;
    if (nf) LocalFree(src);
    info->dwVersion = CARD_FILE_INFO_CURRENT_VERSION;
    info->cbFileSize = len;
    info->AccessCondition = EveryoneReadAdminWriteAc;
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdQueryFreeSpace(PCARD_DATA cd, DWORD flags, PCARD_FREE_SPACE_INFO info)
{
    (void)cd; (void)flags; LOG("CardQueryFreeSpace");
    if (!info) return ERROR_INVALID_PARAMETER;
    info->dwVersion = CARD_FREE_SPACE_INFO_CURRENT_VERSION;
    info->dwBytesAvailable = 0;
    info->dwKeyContainersAvailable = 0;
    info->dwMaxKeyContainers = 0;
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdQueryKeySizes(PCARD_DATA cd, DWORD keySpec, DWORD flags, PCARD_KEY_SIZES sizes)
{
    (void)cd; (void)flags; LOG("CardQueryKeySizes %lu", (unsigned long)keySpec);
    if (!sizes) return ERROR_INVALID_PARAMETER;
    if (keySpec != AT_KEYEXCHANGE && keySpec != AT_SIGNATURE && keySpec != AT_ECDSA_P256) return SCARD_E_UNSUPPORTED_FEATURE;
    sizes->dwVersion = CARD_KEY_SIZES_CURRENT_VERSION;
    sizes->dwMinimumBitlen = 1024; sizes->dwDefaultBitlen = 2048; sizes->dwMaximumBitlen = 4096; sizes->dwIncrementalBitlen = 1024;
    return SCARD_S_SUCCESS;
}

/* ---- signing ---- */

static const BYTE kSha1[]   = { 0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05, 0x00, 0x04, 0x14 };
static const BYTE kSha256[] = { 0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20 };
static const BYTE kSha384[] = { 0x30, 0x41, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30 };
static const BYTE kSha512[] = { 0x30, 0x51, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40 };
static const BYTE kMd5[]    = { 0x30, 0x20, 0x30, 0x0C, 0x06, 0x08, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x05, 0x05, 0x00, 0x04, 0x10 };

static const BYTE *prefixFor(const WCHAR *name, ALG_ID alg, DWORD *plen)
{
#define P(a) (*plen = sizeof a, a)
    if (name) {
        if (!_wcsicmp(name, L"SHA1")) return P(kSha1);
        if (!_wcsicmp(name, L"SHA256")) return P(kSha256);
        if (!_wcsicmp(name, L"SHA384")) return P(kSha384);
        if (!_wcsicmp(name, L"SHA512")) return P(kSha512);
        if (!_wcsicmp(name, L"MD5")) return P(kMd5);
        *plen = 0; return NULL;
    }
    switch (alg) {
    case CALG_SHA1: return P(kSha1);
    case CALG_SHA_256: return P(kSha256);
    case CALG_SHA_384: return P(kSha384);
    case CALG_SHA_512: return P(kSha512);
    case CALG_MD5: return P(kMd5);
    default: *plen = 0; return NULL;   /* CALG_SSL3_SHAMD5 (36 bytes) and "no hash": no DigestInfo */
    }
#undef P
}

/* MGF1 + EMSA-PSS (RFC 8017 9.1.1) with BCrypt hashes */
static NTSTATUS hashOf(const WCHAR *alg, const BYTE *a, DWORD an, const BYTE *b, DWORD bn, const BYTE *c, DWORD cn, BYTE *out, DWORD *outLen)
{
    BCRYPT_ALG_HANDLE h = NULL; BCRYPT_HASH_HANDLE hh = NULL; NTSTATUS st; DWORD n = 0, got = 0;
    st = BCryptOpenAlgorithmProvider(&h, alg, NULL, 0); if (!NT_SUCCESS(st)) return st;
    st = BCryptGetProperty(h, BCRYPT_HASH_LENGTH, (PUCHAR)&n, sizeof n, &got, 0);
    if (NT_SUCCESS(st)) st = BCryptCreateHash(h, &hh, NULL, 0, NULL, 0, 0);
    if (NT_SUCCESS(st) && an) st = BCryptHashData(hh, (PUCHAR)a, an, 0);
    if (NT_SUCCESS(st) && bn) st = BCryptHashData(hh, (PUCHAR)b, bn, 0);
    if (NT_SUCCESS(st) && cn) st = BCryptHashData(hh, (PUCHAR)c, cn, 0);
    if (NT_SUCCESS(st)) st = BCryptFinishHash(hh, out, n, 0);
    if (hh) BCryptDestroyHash(hh);
    BCryptCloseAlgorithmProvider(h, 0);
    *outLen = n;
    return st;
}

static int pssEncode(const WCHAR *alg, const BYTE *mHash, DWORD hLen, DWORD saltLen, DWORD modBits, BYTE *em, DWORD emLen)
{
    BYTE salt[64], h[64], dbMask[600], zeros[8] = { 0 }; DWORD hl = 0, i, dbLen, counter, off = 0;
    if (saltLen > sizeof salt || emLen < hLen + saltLen + 2) return 0;
    if (saltLen && !NT_SUCCESS(BCryptGenRandom(NULL, salt, saltLen, BCRYPT_USE_SYSTEM_PREFERRED_RNG))) return 0;
    {   /* H = Hash(8 zeros || mHash || salt) */
        BCRYPT_ALG_HANDLE ah = NULL; BCRYPT_HASH_HANDLE hh = NULL; NTSTATUS st;
        st = BCryptOpenAlgorithmProvider(&ah, alg, NULL, 0); if (!NT_SUCCESS(st)) return 0;
        st = BCryptCreateHash(ah, &hh, NULL, 0, NULL, 0, 0);
        if (NT_SUCCESS(st)) st = BCryptHashData(hh, zeros, 8, 0);
        if (NT_SUCCESS(st)) st = BCryptHashData(hh, (PUCHAR)mHash, hLen, 0);
        if (NT_SUCCESS(st) && saltLen) st = BCryptHashData(hh, salt, saltLen, 0);
        if (NT_SUCCESS(st)) st = BCryptFinishHash(hh, h, hLen, 0);
        if (hh) BCryptDestroyHash(hh);
        BCryptCloseAlgorithmProvider(ah, 0);
        if (!NT_SUCCESS(st)) return 0;
        hl = hLen;
    }
    dbLen = emLen - hl - 1;
    if (dbLen > sizeof dbMask) return 0;
    for (counter = 0; off < dbLen; counter++) {   /* MGF1(H, dbLen) */
        BYTE c4[4] = { (BYTE)(counter >> 24), (BYTE)(counter >> 16), (BYTE)(counter >> 8), (BYTE)counter }, dg[64]; DWORD dl = 0;
        if (!NT_SUCCESS(hashOf(alg, h, hl, c4, 4, NULL, 0, dg, &dl))) return 0;
        for (i = 0; i < dl && off < dbLen; i++) dbMask[off++] = dg[i];
    }
    memset(em, 0, emLen);
    em[dbLen - saltLen - 1] = 0x01;
    memcpy(em + dbLen - saltLen, salt, saltLen);
    for (i = 0; i < dbLen; i++) em[i] ^= dbMask[i];
    memcpy(em + dbLen, h, hl);
    em[emLen - 1] = 0xBC;
    em[0] &= (BYTE)(0xFF >> (8 * emLen - (modBits - 1)));
    return 1;
}

/* MSE SET + PSO. alg 2: the card pads a DigestInfo; alg 0: raw block (first byte in P2). */
static DWORD cardSign(PCARD_DATA cd, WORD keyFile, BYTE alg, const BYTE *data, DWORD n, BYTE *sig, DWORD sigCap, DWORD *sigLen)
{
    BYTE mse[12] = { 0x00, 0x22, 0x41, 0xB6, 0x07, 0x80, 0x01, alg, 0x84, 0x02, (BYTE)(keyFile >> 8), (BYTE)keyFile };
    BYTE pso[300]; DWORD pl; WORD sw = 0; LONG rc;
    rc = apdu(cd, mse, sizeof mse, NULL, 0, NULL, &sw);
    if (rc == SCARD_S_SUCCESS && sw != 0x9000) {      /* another app may have left a different applet selected */
        rc = selectApplet(cd); if (rc) return rc;
        rc = apdu(cd, mse, sizeof mse, NULL, 0, NULL, &sw);
    }
    if (rc != SCARD_S_SUCCESS) return rc;
    if (sw != 0x9000) { LOG("MSE SET: %04X", sw); return SCARD_E_UNEXPECTED; }
    if (alg == 0x02) {
        if (n > 0xFF) return SCARD_E_INVALID_PARAMETER;
        pso[0] = 0x00; pso[1] = 0x2A; pso[2] = 0x9E; pso[3] = 0x00; pso[4] = (BYTE)n; memcpy(pso + 5, data, n); pso[5 + n] = 0x00; pl = 6 + n;
    } else {
        if (n < 2 || n - 1 > 0xFF) return SCARD_E_INVALID_PARAMETER;
        pso[0] = 0x00; pso[1] = 0x2A; pso[2] = 0x9E; pso[3] = data[0]; pso[4] = (BYTE)(n - 1); memcpy(pso + 5, data + 1, n - 1); pso[4 + n] = 0x00; pl = 5 + n;
    }
    rc = apdu(cd, pso, pl, sig, sigCap, sigLen, &sw);
    if (rc != SCARD_S_SUCCESS) return rc;
    LOG("PSO: %04X, %lu bytes", sw, (unsigned long)*sigLen);
    if (sw == 0x9000 && *sigLen) return SCARD_S_SUCCESS;
    if (sw == 0x6982) return SCARD_W_SECURITY_VIOLATION;   /* PIN not verified yet: the CSP asks for it and retries */
    if (sw == 0x6983) return SCARD_W_CHV_BLOCKED;
    return SCARD_E_UNEXPECTED;
}

static DWORD WINAPI MdSignData(PCARD_DATA cd, PCARD_SIGNING_INFO si)
{
    MD *m = md(cd); Pair *pr; DWORD k, flags, rc, sl = 0, i; BYTE block[600], sig[600]; BYTE alg; const BYTE *send; DWORD sn;
    if (!si) return ERROR_INVALID_PARAMETER;
    if (g_beSig < 0) g_beSig = (int)regDword(L"SigBigEndian", 0);
    if (g_revHash < 0) g_revHash = (int)regDword(L"ReverseHashInput", 0);
    LOG("CardSignData container %u keyspec %lu flags %08lX hash %08lX padtype %lu bytes %lu",
        si->bContainerIndex, (unsigned long)si->dwKeySpec, (unsigned long)si->dwSigningFlags, (unsigned long)si->aiHashAlg,
        (unsigned long)si->dwPaddingType, (unsigned long)si->cbData);
    rc = loadObjects(cd, m); if (rc) return rc;
    if (si->bContainerIndex >= m->nPairs) return SCARD_E_NO_KEY_CONTAINER;
    pr = &m->pairs[si->bContainerIndex];
    k = (pr->bits + 7) / 8;
    flags = si->dwSigningFlags;
    if (flags & CARD_BUFFER_SIZE_ONLY) { si->cbSignedData = k; return SCARD_S_SUCCESS; }
    if (!si->pbData || si->cbData == 0) return ERROR_INVALID_PARAMETER;

    if (flags & CARD_PADDING_INFO_PRESENT) {
        if (si->dwPaddingType == CARD_PADDING_PKCS1) {
            BCRYPT_PKCS1_PADDING_INFO *pi = (BCRYPT_PKCS1_PADDING_INFO *)si->pPaddingInfo; DWORD pl = 0;
            const BYTE *pre = NULL;
            if (pi && pi->pszAlgId && _wcsicmp(pi->pszAlgId, L"SHAMD5") != 0) {   /* "SHAMD5" = TLS 1.0/1.1: 36 bytes, no DigestInfo */
                pre = prefixFor(pi->pszAlgId, 0, &pl);
                if (!pre) return SCARD_E_UNSUPPORTED_FEATURE;
            }
            if (pre) memcpy(block, pre, pl); memcpy(block + pl, si->pbData, si->cbData);
            send = block; sn = pl + si->cbData; alg = 0x02;
        } else if (si->dwPaddingType == CARD_PADDING_PSS) {
            BCRYPT_PSS_PADDING_INFO *pi = (BCRYPT_PSS_PADDING_INFO *)si->pPaddingInfo;
            if (!pi || !pi->pszAlgId) return ERROR_INVALID_PARAMETER;
            if (!pssEncode(pi->pszAlgId, si->pbData, si->cbData, pi->cbSalt, pr->bits, block + (k - (pr->bits + 6) / 8), (pr->bits + 6) / 8)) return SCARD_E_UNEXPECTED;
            memset(block, 0, k - (pr->bits + 6) / 8);
            send = block; sn = k; alg = 0x00;
        } else if (si->dwPaddingType == CARD_PADDING_NONE) {
            if (si->cbData != k) return SCARD_E_INVALID_PARAMETER;
            send = si->pbData; sn = si->cbData; alg = 0x00;
        } else return SCARD_E_UNSUPPORTED_FEATURE;
    } else {
        /* legacy CryptoAPI: the hash algorithm tells the DigestInfo; CRYPT_NOHASHOID (1) leaves it out */
        DWORD pl = 0; const BYTE *pre = (flags & 0x00000001) ? NULL : prefixFor(NULL, si->aiHashAlg, &pl);
        if (pre == NULL) pl = 0;
        for (i = 0; i < si->cbData; i++) block[pl + i] = si->pbData[g_revHash ? si->cbData - 1 - i : i];
        if (pre) memcpy(block, pre, pl);
        send = block; sn = pl + si->cbData; alg = 0x02;
    }

    rc = cardSign(cd, pr->keyFile, alg, send, sn, sig, sizeof sig, &sl);
    if (rc != SCARD_S_SUCCESS) return rc;
    if (sl != k) { LOG("signature length %lu, expected %lu", (unsigned long)sl, (unsigned long)k); return SCARD_E_UNEXPECTED; }
    si->cbSignedData = k;
    si->pbSignedData = cspAlloc(cd, k);
    if (!si->pbSignedData) return ERROR_NOT_ENOUGH_MEMORY;
    for (i = 0; i < k; i++) si->pbSignedData[i] = g_beSig == 1 ? sig[i] : sig[k - 1 - i];   /* CryptoAPI wants little-endian */
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdRsaDecrypt(PCARD_DATA cd, PCARD_RSA_DECRYPT_INFO ri) { (void)cd; (void)ri; return SCARD_E_UNSUPPORTED_FEATURE; }
static DWORD WINAPI MdDhAgreement(PCARD_DATA cd, PCARD_DH_AGREEMENT_INFO di) { (void)cd; (void)di; return SCARD_E_UNSUPPORTED_FEATURE; }

/* ---- properties ---- */

static DWORD putData(PBYTE dst, DWORD cap, PDWORD outLen, const void *src, DWORD n)
{
    if (outLen) *outLen = n;
    if (!dst) return SCARD_S_SUCCESS;
    if (cap < n) return ERROR_INSUFFICIENT_BUFFER;
    memcpy(dst, src, n);
    return SCARD_S_SUCCESS;
}

static DWORD WINAPI MdGetProperty(PCARD_DATA cd, LPCWSTR prop, PBYTE data, DWORD cap, PDWORD outLen, DWORD flags)
{
    MD *m = md(cd); DWORD v;
    LOG("CardGetProperty %ls flags %lu", prop ? prop : L"(null)", (unsigned long)flags);
    if (!prop || !outLen) return ERROR_INVALID_PARAMETER;
    if (!_wcsicmp(prop, CP_CARD_FREE_SPACE)) {
        CARD_FREE_SPACE_INFO fs; fs.dwVersion = CARD_FREE_SPACE_INFO_CURRENT_VERSION; fs.dwBytesAvailable = 0; fs.dwKeyContainersAvailable = 0; fs.dwMaxKeyContainers = 0;
        return putData(data, cap, outLen, &fs, sizeof fs);
    }
    if (!_wcsicmp(prop, CP_CARD_CAPABILITIES)) {
        CARD_CAPABILITIES c; c.dwVersion = CARD_CAPABILITIES_CURRENT_VERSION; c.fCertificateCompression = TRUE; c.fKeyGen = FALSE;
        return putData(data, cap, outLen, &c, sizeof c);
    }
    if (!_wcsicmp(prop, CP_CARD_KEYSIZES)) {
        CARD_KEY_SIZES s; s.dwVersion = CARD_KEY_SIZES_CURRENT_VERSION; s.dwMinimumBitlen = 1024; s.dwDefaultBitlen = 2048; s.dwMaximumBitlen = 4096; s.dwIncrementalBitlen = 1024;
        return putData(data, cap, outLen, &s, sizeof s);
    }
    if (!_wcsicmp(prop, CP_CARD_READ_ONLY)) { v = TRUE; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_CARD_CACHE_MODE)) { v = CP_CACHE_MODE_NO_CACHE; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_SUPPORTS_WIN_X509_ENROLLMENT)) { v = FALSE; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_CARD_GUID)) { loadObjects(cd, m); return putData(data, cap, outLen, m->cardId, 16); }
    if (!_wcsicmp(prop, CP_CARD_SERIAL_NO)) { loadObjects(cd, m); return putData(data, cap, outLen, m->cardId, 16); }
    if (!_wcsicmp(prop, CP_CARD_LIST_PINS)) { v = 1u << ROLE_USER; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_CARD_AUTHENTICATED_STATE)) { v = m->authenticated; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_CARD_PIN_STRENGTH_VERIFY)) { v = CARD_PIN_STRENGTH_PLAINTEXT; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_KEY_IMPORT_SUPPORT)) { v = 0; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_PADDING_SCHEMES)) { v = CARD_PADDING_NONE | CARD_PADDING_PKCS1 | CARD_PADDING_PSS; return putData(data, cap, outLen, &v, sizeof v); }
    if (!_wcsicmp(prop, CP_CARD_PIN_INFO)) {
        PIN_INFO pi;
        if (flags != ROLE_USER) return SCARD_E_INVALID_PARAMETER;
        memset(&pi, 0, sizeof pi);
        pi.dwVersion = PIN_INFO_CURRENT_VERSION;
        pi.PinType = AlphaNumericPinType;
        pi.dwFlags = 0;
        pi.PinPurpose = PrimaryCardPin;
        pi.dwChangePermission = 0;        /* change the PIN in Super Celik */
        pi.dwUnblockPermission = 0;
        pi.PinCachePolicy.dwVersion = PIN_CACHE_POLICY_CURRENT_VERSION;
        pi.PinCachePolicy.PinCachePolicyType = PinCacheNormal;
        pi.PinCachePolicy.dwPinCachePolicyInfo = 0;
        return putData(data, cap, outLen, &pi, sizeof pi);
    }
    return SCARD_E_UNSUPPORTED_FEATURE;
}

static DWORD WINAPI MdSetProperty(PCARD_DATA cd, LPCWSTR prop, PBYTE data, DWORD n, DWORD flags)
{
    (void)cd; (void)data; (void)n; (void)flags;
    LOG("CardSetProperty %ls", prop ? prop : L"(null)");
    /* the CSP hands over its parent window and PIN context string; nothing to keep */
    if (prop && (!_wcsicmp(prop, CP_PARENT_WINDOW) || !_wcsicmp(prop, CP_PIN_CONTEXT_STRING))) return SCARD_S_SUCCESS;
    return SCARD_E_UNSUPPORTED_FEATURE;
}

static DWORD WINAPI MdGetContainerProperty(PCARD_DATA cd, BYTE idx, LPCWSTR prop, PBYTE data, DWORD cap, PDWORD outLen, DWORD flags)
{
    MD *m = md(cd); DWORD v;
    LOG("CardGetContainerProperty %u %ls", idx, prop ? prop : L"(null)");
    (void)flags;
    if (!prop || !outLen) return ERROR_INVALID_PARAMETER;
    if (loadObjects(cd, m) || idx >= m->nPairs) return SCARD_E_NO_KEY_CONTAINER;
    if (!_wcsicmp(prop, CCP_CONTAINER_INFO)) {
        CONTAINER_INFO ci; DWORD rc = MdGetContainerInfo(cd, idx, 0, &ci);
        if (rc) return rc;
        return putData(data, cap, outLen, &ci, sizeof ci);
    }
    if (!_wcsicmp(prop, CCP_PIN_IDENTIFIER)) { v = ROLE_USER; return putData(data, cap, outLen, &v, sizeof v); }
    return SCARD_E_UNSUPPORTED_FEATURE;
}

static DWORD WINAPI MdSetContainerProperty(PCARD_DATA cd, BYTE idx, LPCWSTR prop, PBYTE data, DWORD n, DWORD flags)
{ (void)cd; (void)idx; (void)prop; (void)data; (void)n; (void)flags; return SCARD_E_UNSUPPORTED_FEATURE; }

/* ---------------------------------------------------------------- CardAcquireContext */

DWORD WINAPI CardAcquireContext(PCARD_DATA cd, DWORD flags)
{
    MD *m; DWORD proto = 0, atrLen = 0, nameLen = 0, state = 0; WCHAR reader[256]; BYTE atr[40]; LONG rc; DWORD rl = 256;
    (void)flags;
    LOG("CardAcquireContext (version %lu)", cd ? (unsigned long)cd->dwVersion : 0);
    if (!cd) return ERROR_INVALID_PARAMETER;
    if (cd->dwVersion < CARD_DATA_VERSION_FOUR) return ERROR_REVISION_MISMATCH;
    if (!cd->pfnCspAlloc || !cd->pfnCspFree || !cd->hScard) return ERROR_INVALID_PARAMETER;

    m = (MD *)LocalAlloc(LPTR, sizeof(MD));
    if (!m) return ERROR_NOT_ENOUGH_MEMORY;
    cd->pvVendorSpecific = m;

    nameLen = rl; atrLen = sizeof atr;
    rc = SCardStatusW(cd->hScard, reader, &nameLen, &state, &proto, atr, &atrLen);
    if (rc != SCARD_S_SUCCESS) { LOG("SCardStatus %08lX", (unsigned long)rc); LocalFree(m); cd->pvVendorSpecific = NULL; return (DWORD)rc; }
    m->pci = proto == SCARD_PROTOCOL_T0 ? SCARD_PCI_T0 : SCARD_PCI_T1;

    /* only cards with the CardEdge applet and at least one certificate / key pair are ours */
    rc = loadObjects(cd, m);
    if (rc != SCARD_S_SUCCESS) { LOG("not a CardEdge card (%08lX)", (unsigned long)rc); MdDeleteContext(cd); return SCARD_E_UNKNOWN_CARD; }

    /* version 6 is all this driver needs (version 7 only adds key import and the CNG algorithm properties) */
    if (cd->dwVersion > CARD_DATA_VERSION_SIX) cd->dwVersion = CARD_DATA_VERSION_SIX;

    cd->pfnCardDeleteContext = MdDeleteContext;
    cd->pfnCardQueryCapabilities = MdQueryCapabilities;
    cd->pfnCardDeleteContainer = MdDeleteContainer;
    cd->pfnCardCreateContainer = MdCreateContainer;
    cd->pfnCardGetContainerInfo = MdGetContainerInfo;
    cd->pfnCardAuthenticatePin = MdAuthenticatePin;
    cd->pfnCardGetChallenge = (PFN_CARD_GET_CHALLENGE)MdUnsupported;
    cd->pfnCardAuthenticateChallenge = (PFN_CARD_AUTHENTICATE_CHALLENGE)MdUnsupported;
    cd->pfnCardUnblockPin = (PFN_CARD_UNBLOCK_PIN)MdUnsupported;
    cd->pfnCardChangeAuthenticator = (PFN_CARD_CHANGE_AUTHENTICATOR)MdUnsupported;
    cd->pfnCardDeauthenticate = MdDeauthenticate;
    cd->pfnCardCreateDirectory = MdCreateDirectory;
    cd->pfnCardDeleteDirectory = MdDeleteDirectory;
    cd->pfnCardCreateFile = MdCreateFile;
    cd->pfnCardReadFile = MdReadFile;
    cd->pfnCardWriteFile = MdWriteFile;
    cd->pfnCardDeleteFile = MdDeleteFile;
    cd->pfnCardEnumFiles = MdEnumFiles;
    cd->pfnCardGetFileInfo = MdGetFileInfo;
    cd->pfnCardQueryFreeSpace = MdQueryFreeSpace;
    cd->pfnCardQueryKeySizes = MdQueryKeySizes;
    cd->pfnCardSignData = MdSignData;
    cd->pfnCardRSADecrypt = MdRsaDecrypt;
    cd->pfnCardConstructDHAgreement = MdDhAgreement;
    if (cd->dwVersion >= CARD_DATA_VERSION_FIVE) {
        cd->pfnCardDeriveKey = (PFN_CARD_DERIVE_KEY)MdUnsupported;
        cd->pfnCardDestroyDHAgreement = (PFN_CARD_DESTROY_DH_AGREEMENT)MdUnsupported;
    }
    if (cd->dwVersion >= CARD_DATA_VERSION_SIX) {
        cd->pfnCardGetChallengeEx = (PFN_CARD_GET_CHALLENGE_EX)MdUnsupported;
        cd->pfnCardAuthenticateEx = MdAuthenticateEx;
        cd->pfnCardChangeAuthenticatorEx = (PFN_CARD_CHANGE_AUTHENTICATOR_EX)MdUnsupported;
        cd->pfnCardDeauthenticateEx = MdDeauthenticateEx;
        cd->pfnCardGetContainerProperty = MdGetContainerProperty;
        cd->pfnCardSetContainerProperty = MdSetContainerProperty;
        cd->pfnCardGetProperty = MdGetProperty;
        cd->pfnCardSetProperty = MdSetProperty;
    }
    LOG("acquired: %d key pair(s)", m->nPairs);
    return SCARD_S_SUCCESS;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r)
{
    (void)r;
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(h);
    return TRUE;
}
