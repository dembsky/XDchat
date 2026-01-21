import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    enum Field {
        case displayName, email, password, confirmPassword, invitationCode
    }

    var body: some View {
        ZStack {
            // Simple dark background
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            // Glass card
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.lg) {
                    // Logo and Title
                    VStack(spacing: Theme.Spacing.md) {
                        Image("AppIconLightPreview")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 80, height: 80)
                            .cornerRadius(18)
                            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)

                        Text("XDchat")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Create your account")
                            .font(Theme.Typography.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, Theme.Spacing.md)

                    // Form
                    VStack(spacing: Theme.Spacing.md) {
                        // Display Name Field
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            TextField("Display Name", text: $viewModel.displayName)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .displayName)
                                .onSubmit {
                                    focusedField = .email
                                }
                        }
                        .padding(Theme.Spacing.md)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focusedField == .displayName ? Theme.Colors.accent : Color.primary.opacity(0.1), lineWidth: 1)
                        )

                        // Email Field
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            TextField("Email", text: $viewModel.email)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .email)
                                .textContentType(.emailAddress)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }
                        .padding(Theme.Spacing.md)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focusedField == .email ? Theme.Colors.accent : Color.primary.opacity(0.1), lineWidth: 1)
                        )

                        // Password Field
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            SecureField("Password (min. 6 characters)", text: $viewModel.password)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .password)
                                .onSubmit {
                                    focusedField = .confirmPassword
                                }
                        }
                        .padding(Theme.Spacing.md)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focusedField == .password ? Theme.Colors.accent : Color.primary.opacity(0.1), lineWidth: 1)
                        )

                        // Confirm Password Field
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "lock.badge.checkmark.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)

                                SecureField("Confirm Password", text: $viewModel.confirmPassword)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .onSubmit {
                                        focusedField = .invitationCode
                                    }
                            }
                            .padding(Theme.Spacing.md)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .confirmPassword ? Theme.Colors.accent : Color.primary.opacity(0.1), lineWidth: 1)
                            )

                            if !viewModel.confirmPassword.isEmpty && viewModel.password != viewModel.confirmPassword {
                                Text("Passwords do not match")
                                    .font(Theme.Typography.footnote)
                                    .foregroundColor(Theme.Colors.error)
                                    .padding(.leading, Theme.Spacing.sm)
                            }
                        }

                        // Invitation Code Field
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "ticket.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            TextField("Invitation Code", text: $viewModel.invitationCode)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .invitationCode)
                                .onSubmit {
                                    Task {
                                        await viewModel.register()
                                    }
                                }
                        }
                        .padding(Theme.Spacing.md)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focusedField == .invitationCode ? Theme.Colors.accent : Color.primary.opacity(0.1), lineWidth: 1)
                        )

                        Text("Required for new users")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Theme.Spacing.sm)
                    }

                    // Error Message
                    if viewModel.showError, let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(Theme.Spacing.sm)
                            .frame(maxWidth: .infinity)
                            .background(Theme.Colors.error.opacity(0.9))
                            .cornerRadius(8)
                    }

                    // Register Button
                    Button {
                        Task {
                            await viewModel.register()
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Create Account")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading || !viewModel.isRegisterFormValid)
                    .opacity(viewModel.isRegisterFormValid ? 1 : 0.5)
                    .padding(.top, Theme.Spacing.sm)

                    // Login Link
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Already have an account?")
                            .foregroundColor(.secondary)

                        Button("Sign In") {
                            viewModel.toggleMode()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.Colors.accent)
                        .fontWeight(.semibold)
                    }
                    .font(Theme.Typography.callout)
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(Theme.Spacing.xl)
            }
            .frame(width: 380, height: 580)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
        }
        .frame(minWidth: 500, minHeight: 650)
        .onAppear {
            focusedField = .displayName
        }
    }
}

#Preview {
    RegisterView(viewModel: AuthViewModel())
}
