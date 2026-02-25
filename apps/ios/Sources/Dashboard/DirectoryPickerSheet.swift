import SwiftUI

struct DirectoryPickerSheet: View {
    let recentDirectories: [String]
    @Binding var selectedDirectory: String
    var onDone: () -> Void

    @State private var customPath: String = ""

    var body: some View {
        VStack(spacing: 20) {
            title
            recentSection
            customSection
            doneButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x1C1C1E).ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Title

    private var title: some View {
        Text("Working Directory")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    // MARK: - Recent Directories

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Directories")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.5))

            ForEach(recentDirectories, id: \.self) { dir in
                let isSelected = dir == selectedDirectory
                HStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 3, height: 20)
                    }
                    Text(dir)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.5))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.06))
                .cornerRadius(10)
                .onTapGesture { selectedDirectory = dir }
            }
        }
    }

    // MARK: - Custom Path

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Path")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.5))

            TextField("Enter a directory path...", text: $customPath)
                .font(.system(size: 14, design: .monospaced))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .onSubmit {
                    guard !customPath.isEmpty else { return }
                    selectedDirectory = customPath
                }
        }
    }

    // MARK: - Done

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(14)
        }
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

#Preview {
    DirectoryPickerSheet(
        recentDirectories: [
            "~/projects/my-app",
            "~/projects/api",
            "~/web",
        ],
        selectedDirectory: .constant("~/projects/my-app"),
        onDone: {}
    )
}
