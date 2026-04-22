---
name: msi-repair-status
description: Query MSI China repair progress when a user provides an RMA number and product serial number, needs status interpretation from https://account.msi.cn/zh-Hans/services/inquiry-history, wants change comparison against the last successful result, or needs the required reminder wording when the status implies user action. Use it to fetch the captcha image, collect a user-confirmed captcha answer that may come from manual reading or auxiliary recognition, submit the query, and report the current status plus whether it changed since the last successful check.
---

# MSI Repair Status

Use `scripts/msi-repair-query.sh` for MSI China repair-order lookups. Prefer this skill over browser automation because the site exposes a direct captcha image endpoint and an AJAX detail endpoint.

## Main Responsibility

- Query MSI China repair progress from an `RMA` number and product serial number.
- Interpret the returned status text and the highlighted workflow stage from the success-page workflow widget.
- Compare the latest successful result against the previous successful result for the same `RMA + serial` pair.
- Output the required reminder wording when the result implies user action.

## Workflow

1. Run `scripts/msi-repair-query.sh --rma '<RMA>' --serial '<SERIAL>'`.
2. Let the script download the captcha image and open it locally when possible.
3. Show the captcha to the user. The answer may come from:
   - manual reading by the user
   - auxiliary recognition used only as a suggestion
4. Before submission, ask the user to confirm the final captcha answer or override it. Do not submit an unconfirmed answer.
   If the shell command is run with `--answer`, treat that explicit CLI value as already confirmed by the caller and do not prompt again.
5. Send the confirmed answer back to the running command.
6. Report the result in Chinese:
   - current status first
   - highlighted stage after the current status block
   - whether it changed since the last successful run
   - the required reminder wording when the result implies user action

## Guardrails

- The final captcha answer must be confirmed or overridden by the user before submission.
- An explicit CLI `--answer` is the non-interactive boundary for an already confirmed captcha answer.
- If the site adds another verification step, blocks access, or the HTML shape changes enough that the script cannot extract `_token`, stop and explain the blocker plainly.
- If the returned structure no longer matches the parsing assumptions, including when the success-page workflow widget exists but no highlighted `active` stage can be parsed, stop instead of guessing.
- If the result mentions `待寄送`, `即将失效`, `已失效`, or any clear user-action requirement, repeat this reminder exactly:
  `维修单号 14 天内未寄回会失效，寄出前确认外观完好且产品条码、二维码清晰完整。`

## Artifacts

- The script stores per-run artifacts under `${XDG_CACHE_HOME:-$HOME/.cache}/msi-repair-status/runs`.
- The latest successful result for each `RMA + serial` pair is stored under `${XDG_STATE_HOME:-$HOME/.local/state}/msi-repair-status`.
- When the plain-text output is ambiguous, inspect `result.raw` before inferring the stage.

## References

- Read `references/msi-member-center.md` when you need the endpoint details or the current parsing assumptions.
