import SwiftUI

struct PlanReviewSheet: View {
    let agentName: String
    let planContent: String
    var onApprove: (String?) -> Void
    var onReject: (String?) -> Void

    @State private var note = ""

    private static let bg = Color(red: 0.11, green: 0.11, blue: 0.12)
    private static let border = Color.white.opacity(0.15)
    private static let textColor = Color(white: 0.9)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Plan Review")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 12)
            Text("Agent: \(agentName)")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.top, 4)
                .padding(.bottom, 12)

            Divider().background(Self.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(parseLines().enumerated()), id: \.offset) { _, element in
                        element
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 12) {
                Divider().background(Self.border)

                TextField("Leave a note...", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Button {
                        onReject(note.isEmpty ? nil : note)
                    } label: {
                        Text("Reject")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(14)
                    }

                    Button {
                        onApprove(note.isEmpty ? nil : note)
                    } label: {
                        Text("✅ Approve")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .layoutPriority(1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Self.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: - Markdown Parsing
    private func parseLines() -> [AnyView] {
        planContent.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return AnyView(Spacer().frame(height: 8))
            }
            if trimmed.hasPrefix("## ") {
                return AnyView(
                    Text(String(trimmed.dropFirst(3)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                )
            }
            if let range = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let num = trimmed[range].trimmingCharacters(in: .whitespaces)
                let rest = String(trimmed[range.upperBound...])
                return AnyView(
                    HStack(alignment: .top, spacing: 4) {
                        Text(num).font(.system(size: 15)).foregroundColor(.gray)
                            .frame(width: 24, alignment: .trailing)
                        Text(rest).font(.system(size: 15)).foregroundColor(Self.textColor)
                            .lineSpacing(4)
                    }
                    .padding(.leading, 8)
                )
            }
            if trimmed.hasPrefix("- ") {
                return AnyView(
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 15)).foregroundColor(.gray)
                            .frame(width: 16, alignment: .center)
                        Text(String(trimmed.dropFirst(2)))
                            .font(.system(size: 15)).foregroundColor(Self.textColor)
                            .lineSpacing(4)
                    }
                    .padding(.leading, 8)
                )
            }
            return AnyView(
                Text(trimmed)
                    .font(.system(size: 15))
                    .foregroundColor(Self.textColor)
                    .lineSpacing(4)
            )
        }
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        PlanReviewSheet(
            agentName: "reviewer",
            planContent: """
            ## Goal
            Migrate user table from SQLite to PG

            ## Steps
            1. Create PostgreSQL schema
            2. Write migration script
            3. Update ORM config

            ## Impact
            - Modify 5 files
            """,
            onApprove: { _ in },
            onReject: { _ in }
        )
    }
}
