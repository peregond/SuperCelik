// Minimal hand-written declarations of the PC/SC API in Apple's PCSC.framework.
// Apple's own headers/modules cannot be imported from Swift ("module 'PCSC' is incompatible
// with feature 'swift'"), so the few functions we use are declared here; the symbols are
// resolved at link time from /System/Library/Frameworks/PCSC.framework.
#ifndef CPCSC_H
#define CPCSC_H

#include <stdint.h>

typedef int32_t LONG;
typedef uint32_t DWORD;
typedef int32_t SCARDCONTEXT;
typedef int32_t SCARDHANDLE;

typedef struct {
    uint32_t dwProtocol;
    uint32_t cbPciLength;
} SCARD_IO_REQUEST;

enum {
    SCARD_SCOPE_SYSTEM = 2,
    SCARD_SHARE_SHARED = 2,
    SCARD_PROTOCOL_T0 = 1,
    SCARD_PROTOCOL_T1 = 2,
    SCARD_LEAVE_CARD = 0,
    SCARD_ATTR_ATR_STRING = 0x00090303,
};

LONG SCardEstablishContext(DWORD dwScope, const void *pvReserved1, const void *pvReserved2,
                           SCARDCONTEXT *phContext);
LONG SCardReleaseContext(SCARDCONTEXT hContext);
LONG SCardListReaders(SCARDCONTEXT hContext, const char *mszGroups, char *mszReaders,
                      DWORD *pcchReaders);
LONG SCardConnect(SCARDCONTEXT hContext, const char *szReader, DWORD dwShareMode,
                  DWORD dwPreferredProtocols, SCARDHANDLE *phCard, DWORD *pdwActiveProtocol);
LONG SCardDisconnect(SCARDHANDLE hCard, DWORD dwDisposition);
LONG SCardTransmit(SCARDHANDLE hCard, const SCARD_IO_REQUEST *pioSendPci,
                   const uint8_t *pbSendBuffer, DWORD cbSendLength,
                   SCARD_IO_REQUEST *pioRecvPci, uint8_t *pbRecvBuffer, DWORD *pcbRecvLength);
LONG SCardGetAttrib(SCARDHANDLE hCard, DWORD dwAttrId, uint8_t *pbAttr, DWORD *pcbAttrLen);

#endif
