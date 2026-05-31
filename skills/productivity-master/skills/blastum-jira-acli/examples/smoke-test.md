# Jira ACLI Smoke Test

**Prerequisite**: ACLI authenticated (`acli jira auth login` done).

## Steps

1. **Create** test issue with md→ADF description
   - `echo "# Test\n\nBody" > tmp.md && md-to-adf convert tmp.md > tmp.adf.json`
   - `acli jira workitem create --summary "Smoke test" --project PROJ --type Task --description-file tmp.adf.json`
   - Note the returned key (e.g. PROJ-123)

2. **View** the issue
   - `acli jira workitem view PROJ-123`

3. **Search** for it
   - `acli jira workitem search --jql "key = PROJ-123" --json`

4. **Comment** with md→ADF
   - `echo "Comment body" > comment.md && md-to-adf convert comment.md > comment.adf.json`
   - `acli jira workitem comment create --key PROJ-123 --body-file comment.adf.json`

5. **Edit** summary
   - `acli jira workitem edit --key PROJ-123 --summary "Smoke test (updated)" --yes`

6. **Transition** (if workflow allows)
   - `acli jira workitem transition --key PROJ-123 --status "Done" --yes`

7. **Delete** (or leave for manual cleanup)
   - `acli jira workitem delete --key PROJ-123 --yes`

Replace `PROJ` with your project key.
