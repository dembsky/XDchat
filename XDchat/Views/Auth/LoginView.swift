import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            // Simple dark background
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            // Glass card
            VStack(spacing: Theme.Spacing.xl) {
                // Logo and Title
                VStack(spacing: Theme.Spacing.md) {
                    Image("AppIconLightPreview")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 100, height: 100)
                        .cornerRadius(22)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

                    Text("XDchat")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Sign in to continue")
                        .font(Theme.Typography.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, Theme.Spacing.lg)

                // Form
                VStack(spacing: Theme.Spacing.md) {
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

                        SecureField("Password", text: $viewModel.password)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                Task {
                                    await viewModel.login()
                                }
                            }
                    }
                    .padding(Theme.Spacing.md)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focusedField == .password ? Theme.Colors.accent : Color.primary.opacity(0.1), lineWidth: 1)
                    )

                    // Forgot Password
                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            Task {
                                await viewModel.resetPassword()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accent)
                    }
                    .padding(.top, Theme.Spacing.xs)
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

                // Success Message
                if viewModel.showSuccess, let successMessage = viewModel.successMessage {
                    Text(successMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.9))
                        .cornerRadius(8)
                }

                // Login Button
                Button {
                    Task {
                        await viewModel.login()
                    }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading || !viewModel.isLoginFormValid)
                .opacity(viewModel.isLoginFormValid ? 1 : 0.5)
                .padding(.top, Theme.Spacing.sm)

                // Register Link
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)

                    Button("Sign Up") {
                        viewModel.toggleMode()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.Colors.accent)
                    .fontWeight(.semibold)
                }
                .font(Theme.Typography.callout)
                .padding(.top, Theme.Spacing.md)
            }
            .padding(Theme.Spacing.xxl)
            .frame(width: 380)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            focusedField = .email
        }
    }
}

#Preview {
    LoginView(viewModel: AuthViewModel())
}
