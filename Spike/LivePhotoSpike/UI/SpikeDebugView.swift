import PhotosUI
import SwiftUI

struct SpikeDebugView: View {
    @State private var model = SpikeModel()

    var body: some View {
        NavigationStack {
            List {
                deviceSection
                if let setupError = model.setupError {
                    Section {
                        Text(setupError)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(setupError)")
                    }
                }
                variantsSection
                previewSection
                instructionsSection
            }
            .navigationTitle("Live Photo spike")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save all") {
                        Task { await model.saveAll() }
                    }
                    .disabled(model.isBusy || model.variants.isEmpty)
                    .accessibilityHint("Generates and saves every variant to Photos, one after another.")
                }
            }
        }
        .task {
            model.start()
            // `-APWSaveAllOnLaunch YES` lets scripts capture the screen after a
            // full save without driving the UI.
            if UserDefaults.standard.bool(forKey: "APWSaveAllOnLaunch") {
                await model.saveAll()
            }
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            if let info = model.deviceInfo {
                LabeledContent("Model", value: info.modelIdentifier)
                LabeledContent("System", value: "\(info.systemName) \(info.systemVersion)")
                LabeledContent("Native pixels", value: info.nativePixelSize.description)
                LabeledContent("Native scale", value: String(format: "%.2f", info.nativeScale))
            } else {
                Text("Reading the screen…")
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = model.preview {
            Section {
                LivePhotoPreview(livePhoto: preview)
                    .frame(height: 320)
                    .accessibilityLabel("Preview of the last generated Live Photo. Touch and hold to play.")
            } header: {
                Text("Last generated")
            } footer: {
                Text("\(model.previewVariantLabel ?? ""). Touch and hold to play.")
            }
        }
    }

    private var variantsSection: some View {
        Section {
            ForEach(model.variants) { variant in
                VariantRow(variant: variant, status: model.status(of: variant), isBusy: model.isBusy) {
                    Task { await model.save(variant) }
                }
            }
            Button("Check saved variants in Photos") {
                Task { await model.verifySaved() }
            }
            .disabled(model.isBusy)
            .accessibilityHint("Asks for read access, then checks each saved variant is stored as a Live Photo.")
        } header: {
            Text("Variants")
        } footer: {
            Text("Each variant is rendered at this screen's native pixel size and saved as one Live Photo.")
        }
    }

    private var instructionsSection: some View {
        Section("Trying a variant as a wallpaper") {
            Text("""
            1. Save the variants, then open Photos.
            2. Open a variant (the label on the image says which one), tap Share, then Use as Wallpaper.
            3. Note whether the Live Photo button is available, or whether it says motion is not available.
            4. Add the wallpaper, lock the phone, wake it and note whether the Lock Screen moves.
            5. Record the result per variant and iOS version in docs/DECISIONS.md.
            """)
            .font(.footnote)
        }
    }
}

private struct VariantRow: View {
    let variant: LivePhotoVariant
    let status: SpikeModel.VariantStatus
    let isBusy: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(variant.label).font(.body.monospacedDigit())
                statusText.font(.caption)
            }
            Spacer()
            Button("Save", action: onSave)
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityLabel("Save \(variant.label)")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .idle:
            Text("Not saved yet").foregroundStyle(.secondary)
        case .rendering(let fraction):
            Text("Rendering \(Int((fraction * 100).rounded()))%").foregroundStyle(.secondary)
        case .saving:
            Text("Saving to Photos…").foregroundStyle(.secondary)
        case .saved(_, let isLive):
            switch isLive {
            case .some(true): Text("Saved. Photos stored it as a Live Photo.").foregroundStyle(.green)
            case .some(false): Text("Saved, but Photos did NOT store it as a Live Photo.").foregroundStyle(.red)
            case .none: Text("Saved. Not checked (no read access).").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text("Failed: \(message)").foregroundStyle(.red)
        }
    }
}

/// Hosts `PHLivePhotoView`, which plays the motion on touch and hold.
private struct LivePhotoPreview: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto {
            view.livePhoto = livePhoto
        }
    }
}

#Preview {
    SpikeDebugView()
}
