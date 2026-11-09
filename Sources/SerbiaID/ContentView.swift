import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                PersonalView().tabItem { Label(loc.t(.tabPersonal), systemImage: "person.text.rectangle") }
                TokenView().tabItem { Label(loc.t(.tabToken), systemImage: "key.viewfinder") }
                AboutView().tabItem { Label(loc.t(.tabAbout), systemImage: "info.circle") }
            }
        }
        .alert(loc.t(.error), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(loc.t(.ok), role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            Text(loc.t(.reader)).bold()
            Picker("", selection: $model.selectedReader) {
                if model.readers.isEmpty { Text(loc.t(.noReader)).tag("") }
                ForEach(model.readers, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(maxWidth: 280)
            Button(loc.t(.refresh)) { model.refresh() }
            Label(model.cardPresent ? loc.t(.cardPresent) : loc.t(.noCard),
                  systemImage: model.cardPresent ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(model.cardPresent ? .green : .secondary)
            Spacer()
            Picker(loc.t(.language), selection: $loc.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(width: 240)
        }.padding()
    }
}

struct PersonalView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button(loc.t(.readCard)) { model.readCard() }
                    .disabled(!model.cardPresent).keyboardShortcut("r")
                Button(loc.t(.printCard)) { if let p = model.personal { Printer.print(p, loc: loc) } }
                    .disabled(model.personal == nil).keyboardShortcut("p")
                Button(loc.t(.verifySignature)) { model.verifySignatures() }
                    .disabled(!model.cardPresent)
                sigLabel
                if let atr = model.atrHex { Text("\(loc.t(.atr)): \(atr)").font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            if let p = model.personal {
                HStack(alignment: .top, spacing: 20) {
                    Group {
                        if let d = p.portrait, let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().scaledToFit()
                        } else {
                            Image(systemName: "person.crop.rectangle").resizable().scaledToFit().foregroundStyle(.secondary)
                        }
                    }.frame(width: 150, height: 190)
                    Form {
                        let f = p.fixed, d = p.document
                        row(.surname, f.surname); row(.givenName, f.givenName)
                        if p.cardType == .id2008 || p.cardType == .id2014 { row(.parentName, f.parentGivenName) }
                        row(.dob, f.dateOfBirth); row(.sex, f.sex)
                        row(.placeOfBirth, [f.placeOfBirth, f.communityOfBirth, f.stateOfBirth].filter { !$0.isEmpty }.joined(separator: ", "))
                        if !f.nationalityFull.isEmpty { row(.nationality, f.nationalityFull) }
                        row(.jmbg, f.personalNumber)
                        row(.address, p.variable.formatted)
                        row(.docNumber, d.docRegNo)
                        if !d.documentSerialNumber.isEmpty { row(.docSerial, d.documentSerialNumber) }
                        row(.issuedBy, d.issuingAuthority)
                        row(.issueDate, d.issuingDate); row(.expiryDate, d.expiryDate)
                    }
                }
            } else { Spacer() }
        }.padding()
    }

    @ViewBuilder private var sigLabel: some View {
        switch model.signatureStatus {
        case .ok: Label(loc.t(.sigOk), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .chainNotTrusted: Label(loc.t(.sigChain), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .invalid: Label(loc.t(.sigBad), systemImage: "xmark.seal.fill").foregroundStyle(.red)
        case .unavailable: Text(loc.t(.notImplemented)).font(.caption).foregroundStyle(.secondary)
        case nil: EmptyView()
        }
    }

    private func row(_ k: Loc.L, _ v: String) -> some View {
        LabeledContent(loc.t(k)) { Text(v).textSelection(.enabled) }
    }
}

struct TokenView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @State private var old = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var status: String?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading) {
                HStack {
                    Text(loc.t(.certificates)).font(.headline)
                    Spacer()
                    Button(loc.t(.readToken)) { model.readToken() }.disabled(!model.cardPresent)
                }
                if let t = model.token {
                    Text("\(t.tokenLabel) \(t.tokenSerial)").font(.caption).foregroundStyle(.secondary)
                }
                List(model.tokenRows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label.isEmpty ? (row.summary?.subject ?? "") : row.label)
                        if let s = row.summary {
                            Label(s.chainTrusted ? loc.t(.chainOk) : loc.t(.sigChain),
                                  systemImage: s.chainTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(s.chainTrusted ? .green : .orange)
                        }
                    }
                }
                Text(loc.t(.pinNote)).font(.caption).foregroundStyle(.secondary)
            }
            Form {
                Section(loc.t(.changePin)) {
                    if !model.canChangePin {
                        Text(loc.t(.pinUnsupported)).font(.caption).foregroundStyle(.secondary)
                    }
                    SecureField(loc.t(.currentPin), text: $old)
                    SecureField(loc.t(.newPin), text: $new1)
                    SecureField(loc.t(.confirmPin), text: $new2)
                    Button(loc.t(.changePin)) { submit() }
                        .disabled(!model.canChangePin || old.isEmpty || new1.count < 5 || new1.count > 16)
                    if let s = status { Text(s).font(.caption) }
                }
            }.frame(width: 300)
        }.padding()
    }

    private func submit() {
        guard new1 == new2 else { status = loc.t(.pinMismatch); return }
        do {
            _ = try model.changePin(old: old, new: new1)
            status = loc.t(.pinChanged); old = ""; new1 = ""; new2 = ""
        } catch CardError.notImplemented { status = loc.t(.notImplemented) }
        catch CardError.unsupportedForCard { status = loc.t(.pinUnsupported) }
        catch { status = loc.t(.pinFailed) + ": " + error.localizedDescription }
    }

    private func certName(_ t: EidCertType) -> String {
        switch t {
        case .moiIntermediateCA: return loc.t(.certMoiCA)
        case .user1Auth: return loc.t(.certAuth)
        case .user2Sign: return loc.t(.certSign)
        case .sigFixed: return loc.t(.certSigFixed)
        case .sigVariable: return loc.t(.certSigVariable)
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var loc: Loc
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key").font(.system(size: 56))
            Text(loc.t(.appTitle)).font(.title)
            Text(loc.t(.aboutText)).multilineTextAlignment(.center).frame(maxWidth: 420)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
