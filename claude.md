# Claude Code Instructions

## PR Submission (IMPORTANT)
When creating or updating a PR:
1. Squash all commits into a single commit for easier review
2. Run `flutter build web --release` before the final commit
3. Include web build: `git add -f build/web`
4. Use a clear, descriptive commit message summarizing all changes

This ensures clean PRs and Vercel can deploy a preview of the Flutter web app.

## todo.md
If user asks to process todo.md, look at todo.md, pick next incomplete task and complete it and mark as completed. Then repeat for each incomplete task in todo.md.