# Contributing to XDchat

Thank you for your interest in contributing to XDchat!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/XDchat.git`
3. Follow the setup instructions in [README.md](README.md)
4. Create a feature branch: `git checkout -b feat/your-feature`

## Development Setup

Make sure you have:
- macOS 15.0+ (Sequoia)
- Xcode 16.0+
- A Firebase project configured
- A Giphy API key

Copy `Config.xcconfig.example` to `Config.xcconfig` and fill in your API keys.

## Branch Naming

Use prefixes:
- `feat/` - New features
- `fix/` - Bug fixes
- `refactor/` - Code refactoring
- `docs/` - Documentation changes

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: Add message reactions
fix: Resolve crash on empty conversation
refactor: Extract message parsing logic
docs: Update setup instructions
```

## Pull Requests

1. Keep PRs focused - one feature or fix per PR
2. Update documentation if needed
3. Test your changes locally before submitting
4. Fill in the PR template

## Code Style

- SwiftUI with MVVM architecture
- Small, focused files (200-400 lines)
- Meaningful variable and function names
- Handle errors properly - no silent failures

## Reporting Issues

Use GitHub Issues with the provided templates. Include:
- Steps to reproduce
- Expected vs actual behavior
- macOS version and any relevant logs

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
