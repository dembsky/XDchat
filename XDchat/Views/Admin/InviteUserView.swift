import SwiftUI

struct InviteUserView: View {
    @StateObject private var viewModel = InvitationViewModel()
    @State private var expirationDays: Int = 7
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Create new invitation section
                    createInvitationSection

                    Divider()

                    // Active invitations section
                    activeInvitationsSection

                    // Used invitations section
                    if !viewModel.usedInvitations.isEmpty {
                        usedInvitationsSection
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .alert("Invitation Created", isPresented: .constant(viewModel.newInvitationCode != nil)) {
            Button("Copy Code") {
                if let code = viewModel.newInvitationCode {
                    viewModel.copyToClipboard(code)
                }
                viewModel.clearNewInvitationCode()
            }
            Button("Close", role: .cancel) {
                viewModel.clearNewInvitationCode()
            }
        } message: {
            if let code = viewModel.newInvitationCode {
                Text("Your invitation code is:\n\n\(code)\n\nShare this code with someone to let them join XDchat.")
            }
        }
        .alert("Copied!", isPresented: $viewModel.showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Invitation code copied to clipboard.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.Colors.accent)

            Spacer()

            Text("Invite Users")
                .font(Theme.Typography.headline)

            Spacer()

            // Placeholder for symmetry
            Button("Close") { }
                .buttonStyle(.plain)
                .opacity(0)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Create Invitation Section

    private var createInvitationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Create New Invitation")
                .font(Theme.Typography.headline)
                .fontWeight(.semibold)

            if viewModel.canCreateInvitations {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Expiration picker
                    HStack {
                        Text("Expires in:")
                            .foregroundColor(.secondary)

                        Picker("", selection: $expirationDays) {
                            Text("1 day").tag(1)
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("Never").tag(0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    // Create button
                    Button {
                        Task {
                            await viewModel.createInvitation(
                                expiresInDays: expirationDays == 0 ? nil : expirationDays
                            )
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Image(systemName: "plus.circle.fill")
                            Text("Generate Invitation Code")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .background(Theme.messengerGradient)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.CornerRadius.medium)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Theme.Colors.warning)

                    Text("You don't have permission to create invitations.")
                        .foregroundColor(.secondary)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.warning.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.medium)
            }
        }
    }

    // MARK: - Active Invitations Section

    private var activeInvitationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Active Invitations")
                    .font(Theme.Typography.headline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(viewModel.activeInvitations.count)")
                    .font(Theme.Typography.callout)
                    .foregroundColor(.secondary)
            }

            if viewModel.activeInvitations.isEmpty {
                Text("No active invitations")
                    .foregroundColor(.secondary)
                    .padding(Theme.Spacing.md)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.activeInvitations) { invitation in
                        InvitationRowView(
                            invitation: invitation,
                            onCopy: { viewModel.copyToClipboard(invitation.code) },
                            onDelete: {
                                Task {
                                    await viewModel.deleteInvitation(invitation)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Used Invitations Section

    private var usedInvitationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Used Invitations")
                    .font(Theme.Typography.headline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(viewModel.usedInvitations.count)")
                    .font(Theme.Typography.callout)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.usedInvitations) { invitation in
                    InvitationRowView(
                        invitation: invitation,
                        onCopy: nil,
                        onDelete: nil
                    )
                }
            }
        }
    }
}

// MARK: - Invitation Row View

struct InvitationRowView: View {
    let invitation: Invitation
    let onCopy: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(invitation.code)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)

                    statusBadge
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Text("Created \(invitation.createdAt.timeAgoDisplay())")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)

                    if let expiresAt = invitation.expiresAt, !invitation.isUsed {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Expires \(expiresAt.timeAgoDisplay())")
                            .font(Theme.Typography.caption)
                            .foregroundColor(invitation.isExpired ? Theme.Colors.error : .secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                if let onCopy = onCopy, invitation.isValid {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Copy code")
                }

                if let onDelete = onDelete, !invitation.isUsed {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(Theme.Colors.error)
                    }
                    .buttonStyle(.plain)
                    .help("Delete invitation")
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color(.textBackgroundColor))
        .cornerRadius(Theme.CornerRadius.medium)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if invitation.isUsed {
            Text("Used")
                .font(Theme.Typography.footnote)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray)
                .clipShape(Capsule())
        } else if invitation.isExpired {
            Text("Expired")
                .font(Theme.Typography.footnote)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Colors.error)
                .clipShape(Capsule())
        } else {
            Text("Active")
                .font(Theme.Typography.footnote)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Colors.online)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    InviteUserView()
}
