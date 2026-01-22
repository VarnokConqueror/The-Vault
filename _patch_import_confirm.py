from pathlib import Path
import re

path = Path(r"lib\screens\profile_screen.dart")
src = path.read_text(encoding="utf-8")

pattern = re.compile(
    r"(FilledButton\.icon\(\s*"
    r"onPressed:\s*\(\)\s*async\s*\{\s*)"
    r"(final\s+ok\s*=\s*await\s+ChatStore\.importChatsJson\(\s*importController\.text\s*\)\s*;\s*)",
    re.DOTALL
)

if not pattern.search(src):
    raise SystemExit("PATCH FAIL: Import call site not found exactly as expected.")

replacement = (
    r"\1"
    r"final raw = importController.text.trim();\n"
    r"                    if (raw.isEmpty) {\n"
    r"                      if (!context.mounted) return;\n"
    r"                      ScaffoldMessenger.of(context).showSnackBar(\n"
    r"                        const SnackBar(content: Text(\"Restore failed...invalid or empty backup.\")),\n"
    r"                      );\n"
    r"                      return;\n"
    r"                    }\n\n"
    r"                    final overwrite = await showDialog<bool>(\n"
    r"                      context: context,\n"
    r"                      barrierDismissible: false,\n"
    r"                      builder: (ctx) {\n"
    r"                        return AlertDialog(\n"
    r"                          title: const Text(\"Overwrite local chats...\"),\n"
    r"                          content: const Text(\n"
    r"                            \"Import replaces your local chats with the pasted backup.\\n\\nThis cannot be undone...\",\n"
    r"                          ),\n"
    r"                          actions: [\n"
    r"                            TextButton(\n"
    r"                              onPressed: () => Navigator.pop(ctx, false),\n"
    r"                              child: const Text(\"Cancel\"),\n"
    r"                            ),\n"
    r"                            TextButton(\n"
    r"                              onPressed: () => Navigator.pop(ctx, true),\n"
    r"                              child: const Text(\"Overwrite\"),\n"
    r"                            ),\n"
    r"                          ],\n"
    r"                        );\n"
    r"                      },\n"
    r"                    );\n\n"
    r"                    if (overwrite != true) return;\n\n"
    r"                    final ok = await ChatStore.importChatsJson(raw);\n"
)

out = pattern.sub(replacement, src, count=1)
path.write_text(out, encoding="utf-8")
print("PATCH OK: Overwrite confirmation added before import.")
