# GitHub Actions CI/CD Workflows

This directory contains the GitHub Actions workflows for continuous integration, deployment, and release automation for Crubik.

## Workflows

### 1. CI Workflow (`ci.yml`)

The main CI workflow runs automatically on every pull request, push to main, and can be triggered manually.

#### Triggers
- **Pull Requests**: Runs on all PRs to validate changes
- **Push to main**: Runs on commits to the main branch
- **Tags**: Runs on version tags (v*)
- **Manual**: Can be triggered via `workflow_dispatch`

#### Jobs

##### Quality Checks
Validates code quality and runs tests:
- ✅ Code formatting check (`dart format`)
- ✅ Static analysis (`flutter analyze`)
- ✅ Unit and widget tests (`flutter test`)
- ✅ Code coverage upload to Codecov (optional)

##### Build Web
- Builds the Flutter web app with optimized release configuration
- Uploads web build as artifact (retained for 30 days)
- **Deployment**: Automatically deploys to GitHub Pages on main branch or tags

##### Build Android
- Builds both APK and App Bundle (AAB) for Android
- Uploads both artifacts (retained for 30 days)
- Requires Java 17 and Gradle caching

##### Build Windows
- Builds Windows desktop application
- Creates a ZIP archive
- Uploads artifact (retained for 30 days)

##### Build macOS
- Builds universal macOS app bundle
- Creates a ZIP archive
- Uploads artifact (retained for 30 days)

##### Build Linux
- Builds Linux desktop application
- Creates a tar.gz archive
- Uploads artifact (retained for 30 days)

##### Deploy Web
- Deploys the web build to GitHub Pages
- Only runs on pushes to main or version tags
- Requires GitHub Pages to be enabled in repository settings

#### Artifacts
All build artifacts are available for download from the Actions tab for 30 days after the workflow run.

### 2. Release Workflow (`release.yml`)

Creates GitHub releases with all platform builds attached when version tags are pushed.

#### Triggers
- **Version Tags**: Automatically runs when a tag starting with `v` is pushed (e.g., `v1.0.0`)
- **Manual**: Can be triggered via `workflow_dispatch`

#### Jobs

##### Create Release (Linux-based)
- Runs quality checks
- Builds Web, Android (APK + AAB), and Linux platforms
- Generates release notes from git commits
- Creates a GitHub Release with:
  - Version-tagged artifacts
  - Auto-generated changelog
  - Download instructions

##### Build Windows for Release
- Runs on a Windows runner
- Builds Windows desktop app
- Attaches to the release

##### Build macOS for Release
- runs on a macOS runner
- Builds macOS desktop app
- Attaches to the release

## Setup Requirements

### Global Configuration Variables

Both workflows use global environment variables where supported by GitHub Actions:

#### Version Control Variables
- `FLUTTER_VERSION`: Flutter SDK version (currently `3.44.6`, from `.fvmrc`)

#### Action Versions and Timeouts

**Important GitHub Actions Limitations**: 
- Action versions (e.g., `actions/checkout@v4`, `subosito/flutter-action@v2`) **must be hardcoded** directly in each `uses:` field. GitHub Actions does not support using environment variables in `uses:` fields.
- Job timeouts **must be literal numbers**. The `timeout-minutes` field cannot reference environment variables.

Current configuration:
- Quality checks and web build jobs: **30 minutes** timeout
- Platform build jobs (Android, Windows, macOS, Linux): **45 minutes** timeout
- Action versions: hardcoded as `v4` for checkout, `v2` for Flutter, `v4` for setup-java, `v4.5.0` for upload-artifact, `v4.1.3` for download-artifact, etc.

To update action versions or timeouts, you must edit each occurrence directly in the workflow YAML files.

### Repository Settings

#### 1. Enable GitHub Pages
**Note**: GitHub Pages deployment is currently disabled in the workflow (`if: false`) as it requires a paid subscription.

To enable web deployment when available:
1. Remove the `if: false` condition from the `deploy-web` job in `ci.yml`
2. Go to **Settings** → **Pages**
3. Under "Build and deployment":
   - Source: **GitHub Actions**
4. Save changes

The web app will be available at: `https://<username>.github.io/<repository>/`

#### 2. (Optional) Enable Codecov
To enable code coverage reporting:
1. Sign up at [codecov.io](https://codecov.io)
2. Add your repository
3. No additional secrets required for public repositories

### Creating a Release

To create a new release with all platform builds:

1. **Update version in `pubspec.yaml`**:
   ```yaml
   version: 1.2.3+4
   ```

2. **Commit the version change**:
   ```bash
   git add pubspec.yaml
   git commit -m "Bump version to 1.2.3"
   git push
   ```

3. **Create and push a version tag**:
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

4. **Wait for workflows to complete**:
   - The Release workflow will automatically create a GitHub Release
   - All platform builds will be attached as downloadable assets

### Manual Workflow Triggers

Both workflows can be triggered manually:

1. Go to **Actions** tab in GitHub
2. Select the workflow (CI or Release)
3. Click **Run workflow**
4. Select the branch and click **Run workflow**

## Development Workflow

### Local Development
Follow the standard development workflow documented in `AGENTS.md`:

```bash
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

### Pull Request Process
1. Create a feature branch
2. Make changes
3. Push to GitHub - CI workflow runs automatically
4. CI validates:
   - Code formatting
   - Static analysis
   - Tests pass
   - All platforms build successfully
5. Review artifacts in the Actions tab if needed
6. Merge when CI passes and review is complete

### Testing Builds Locally
To test platform builds locally before pushing:

```bash
# Web
flutter build web --release

# Android
flutter build apk --release
flutter build appbundle --release

# Desktop (on respective platforms)
flutter build windows --release  # Windows only
flutter build macos --release    # macOS only
flutter build linux --release    # Linux only
```

## Caching Strategy

The workflows use caching to speed up builds:
- **Flutter SDK**: Cached by `subosito/flutter-action`
- **Pub packages**: Automatically cached with Flutter action
- **Gradle**: Cached for Android builds
- **Build artifacts**: Not cached (generated fresh each time)

## Troubleshooting

### Build Failures

**Format check fails**:
```bash
dart format lib test
```

**Analysis errors**:
```bash
flutter analyze
```

**Test failures**:
```bash
flutter test
```

**Build runner errors**:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Artifact Upload Issues
If artifacts fail to upload:
- Check artifact name uniqueness
- Verify path exists after build
- Review workflow logs for specific errors

### GitHub Pages Deployment Issues
If deployment fails:
1. Verify GitHub Pages is enabled with "GitHub Actions" source
2. Check repository permissions for `GITHUB_TOKEN`
3. Ensure base-href matches your repository name
4. Review deployment logs in the workflow run

### Release Creation Issues
If release creation fails:
- Verify the tag follows the `v*` pattern (e.g., `v1.0.0`)
- Check that `GITHUB_TOKEN` has write permissions
- Ensure all required builds complete successfully

## Maintenance

### Updating Flutter Version
To update the Flutter version used in CI:

1. Update `.fvmrc`:
   ```json
   {
     "flutter": "3.xx.x"
   }
   ```

2. Update the `FLUTTER_VERSION` environment variable in both workflow files:
   ```yaml
   env:
     FLUTTER_VERSION: '3.xx.x'
   ```

### Updating Action Versions
All action versions are centralized in the `env:` section at the top of each workflow file. To update:

1. Locate the action version variable (e.g., `UPLOAD_ARTIFACT_ACTION_VERSION`)
2. Update the version in the `env:` section
3. The change will automatically apply to all jobs using that action

Example:
```yaml
env:
  UPLOAD_ARTIFACT_ACTION_VERSION: 'v4.6.0'  # Update this
```

### Updating Timeout Values
Timeout values are also centralized:

```yaml
env:
  TIMEOUT_MINUTES_DEFAULT: 30  # For quality checks and web builds
  TIMEOUT_MINUTES_BUILD: 45    # For platform builds
```

### Adding New Build Targets
To add support for new platforms:

1. Add a new job to `ci.yml`
2. Follow the pattern of existing build jobs
3. Add corresponding release build to `release.yml`
4. Test thoroughly before merging

### Modifying Build Commands
When changing build commands:

1. Test locally first
2. Update both `ci.yml` and `release.yml` consistently
3. Update this README if workflow behavior changes
4. Consider impact on artifact names and paths

## Performance

Typical workflow execution times:
- **Quality Checks**: 5-10 minutes
- **Web Build**: 5-10 minutes
- **Android Build**: 10-15 minutes
- **Windows Build**: 10-15 minutes
- **macOS Build**: 10-15 minutes
- **Linux Build**: 10-15 minutes

Total CI time for all jobs: ~15-20 minutes (jobs run in parallel)

## Security

- No secrets are required for basic CI/CD
- `GITHUB_TOKEN` is automatically provided by GitHub Actions
- Build artifacts are retained for 30 days only
- Generated files (*.g.dart, web/drift_worker.dart.js, web/sqlite3.wasm) are excluded from commits

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Flutter CI/CD Documentation](https://docs.flutter.dev/deployment/cd)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)
- [Semantic Versioning](https://semver.org/)
