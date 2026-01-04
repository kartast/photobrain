# Claude Code Instructions

## PR Submission (IMPORTANT)
When creating or updating a PR:
1. Run `flutter build web` after each commit when Claude Code web is working
2. Include web build: `git add -f build/web`
3. Use a clear, descriptive commit message summarizing all changes

This ensures Vercel can deploy a preview of the Flutter web app with each commit.

## todo.md
If user asks to process todo.md, look at todo.md, pick next incomplete task and complete it and mark as completed. Then repeat for each incomplete task in todo.md.