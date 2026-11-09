import SwiftUI
import AppKit

// Palette: Serbian flag blue / red on system surfaces
let brandBlue = Color(red: 0.047, green: 0.251, blue: 0.463)
let brandRed = Color(red: 0.776, green: 0.212, blue: 0.235)

enum Page: Hashable { case personal, token, about }

// MARK: - Reusable pieces

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var icon: String?
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text).lineLimit(2)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @State private var page: Page = .personal

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            VStack(spacing: 0) {
                updateBanner
                header
                Divider()
                Group {
                    switch page {
                    case .personal: PersonalView()
                    case .token: TokenView()
                    case .about: AboutView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .tint(brandBlue)
        .alert(loc.t(.error), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(loc.t(.ok), role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.checkUpdates(manual: false) }
    }

    private var sidebar: some View {
        List(selection: $page) {
            Label(loc.t(.tabPersonal), systemImage: "person.text.rectangle").tag(Page.personal)
            Label(loc.t(.tabToken), systemImage: "key.viewfinder").tag(Page.token)
            Label(loc.t(.tabAbout), systemImage: "info.circle").tag(Page.about)
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t(.appTitle)).font(.system(size: 16, weight: .bold))
                    Text(loc.t(.brandSub)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Text("\(loc.t(.version)) \(Updater.currentVersion)")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
    }

    @ViewBuilder private var updateBanner: some View {
        if let u = model.update {
            HStack {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(brandBlue)
                Text(model.updating ? loc.t(.updateDownloading)
                                    : String(format: loc.t(.updateAvailable), u.version))
                    .fontWeight(.semibold)
                Spacer()
                Button { Task { await model.installUpdate() } } label: { Label(loc.t(.updateNow), systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).disabled(model.updating)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color.yellow.opacity(0.18))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.selectedReader) {
                if model.readers.isEmpty { Text(loc.t(.noReader)).tag("") }
                ForEach(model.readers, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 260)
            Button { model.refresh() } label: { Label(loc.t(.refresh), systemImage: "arrow.clockwise") }
            Pill(text: model.cardPresent ? loc.t(.cardPresent) : loc.t(.noCard),
                 color: model.cardPresent ? .green : .secondary,
                 icon: model.cardPresent ? "checkmark.circle.fill" : "xmark.circle")
            Spacer()
            Picker("", selection: $loc.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 120)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Personal data

struct PersonalView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Button { model.readCard() } label: { Label(loc.t(.readCard), systemImage: "person.text.rectangle").fontWeight(.semibold) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.cardPresent).keyboardShortcut("r")
                    Button { if let p = model.personal { Printer.print(p, loc: loc) } } label: { Label(loc.t(.printCard), systemImage: "printer") }
                        .controlSize(.large).disabled(model.personal == nil).keyboardShortcut("p")
                    Button { if let p = model.personal { Printer.savePDF(p, loc: loc) } } label: { Label(loc.t(.savePdf), systemImage: "square.and.arrow.down") }
                        .controlSize(.large).disabled(model.personal == nil).keyboardShortcut("s")
                    Button { model.verifySignatures() } label: { Label(loc.t(.verifySignature), systemImage: "checkmark.seal") }
                        .controlSize(.large).disabled(!model.cardPresent)
                    sigPill
                    Spacer()
                }

                if let p = model.personal {
                    HStack(alignment: .top, spacing: 18) {
                        Card {
                            VStack(spacing: 12) {
                                portrait(p)
                                Text("\(p.fixed.givenName) \(p.fixed.surname)")
                                    .font(.system(size: 17, weight: .bold)).multilineTextAlignment(.center)
                                Text(docTypeName(p.cardType)).foregroundStyle(.secondary)
                            }
                            .frame(width: 190)
                        }
                        Card {
                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                                GridItem(.flexible(), alignment: .topLeading)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(rows(p), id: \.0) { row in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(loc.t(row.0)).font(.system(size: 11)).foregroundStyle(.secondary)
                                        Text(row.1).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text(loc.t(.hintRead)).font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 20)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder private var sigPill: some View {
        switch model.signatureStatus {
        case .ok: Pill(text: loc.t(.sigOk), color: .green, icon: "checkmark.seal.fill")
        case .chainNotTrusted: Pill(text: loc.t(.sigChain), color: .orange, icon: "exclamationmark.triangle.fill")
        case .invalid: Pill(text: loc.t(.sigBad), color: .red, icon: "xmark.seal.fill")
        case .unavailable: Text(loc.t(.notImplemented)).font(.caption).foregroundStyle(.secondary)
        case nil: EmptyView()
        }
    }

    @ViewBuilder private func portrait(_ p: PersonalData) -> some View {
        Group {
            if let d = p.portrait, let img = NSImage(data: d) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.rectangle").resizable().scaledToFit().padding(40).foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, height: 215)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func docTypeName(_ t: EidCardType) -> String {
        switch t {
        case .if2020: return loc.t(.docIF)
        case .rp2024: return loc.t(.docRP)
        default: return loc.t(.docID)
        }
    }

    private func rows(_ p: PersonalData) -> [(Loc.L, String)] {
        let f = p.fixed, d = p.document
        var r: [(Loc.L, String)] = [(.surname, f.surname), (.givenName, f.givenName)]
        if p.cardType == .id2008 || p.cardType == .id2014, !f.parentGivenName.isEmpty { r.append((.parentName, f.parentGivenName)) }
        r += [(.dob, f.dateOfBirth), (.sex, f.sex),
              (.placeOfBirth, [f.placeOfBirth, f.communityOfBirth, f.stateOfBirth].filter { !$0.isEmpty }.joined(separator: ", "))]
        if !f.nationalityFull.isEmpty { r.append((.nationality, f.nationalityFull)) }
        r += [(.jmbg, f.personalNumber), (.address, p.variable.formatted), (.docNumber, d.docRegNo)]
        if !d.documentSerialNumber.isEmpty { r.append((.docSerial, d.documentSerialNumber)) }
        r += [(.issuedBy, d.issuingAuthority), (.issueDate, d.issuingDate), (.expiryDate, d.expiryDate)]
        return r
    }
}

// MARK: - Token

struct TokenView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { model.readToken() } label: { Label(loc.t(.readToken), systemImage: "key").fontWeight(.semibold) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.cardPresent)
                    if let t = model.token {
                        Text("\(t.tokenLabel)  \(t.tokenSerial)").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc.t(.certificates)).font(.system(size: 15, weight: .bold))
                        if model.tokenRows.isEmpty {
                            Text(loc.t(.hintToken)).foregroundStyle(.secondary)
                        }
                        ForEach(model.tokenRows) { row in
                            HStack {
                                Text(row.label.isEmpty ? (row.summary?.subject ?? "") : row.label)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                if let s = row.summary {
                                    Pill(text: s.chainTrusted ? loc.t(.chainOk) : loc.t(.sigChain),
                                         color: s.chainTrusted ? .green : .orange,
                                         icon: s.chainTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                }
                            }
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(loc.t(.pinNote)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text(loc.t(.appTitle)).font(.system(size: 26, weight: .bold))
                Text(loc.t(.aboutText)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
                Text("\(loc.t(.version)) \(Updater.currentVersion)").fontWeight(.semibold).padding(.top, 8)
                Button { Task { await model.checkUpdates(manual: true) } } label: { Label(loc.t(.checkUpdates), systemImage: "arrow.triangle.2.circlepath") }
                if let s = model.updateStatus {
                    Text(s).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
