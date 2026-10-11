// Give each configured agent a section without changing its source notes.
import { readFileSync, writeFileSync, existsSync } from "node:fs"
import { join } from "node:path"

const root = process.argv[2]
const agents = JSON.parse(readFileSync("/run/quartz-agents.json", "utf8"))
const links = agents.map(({ id, name }) => `- [[${id}/index|${name}]]`).join("\n")
writeFileSync(join(root, "index.md"), `---\ntitle: Agents\n---\n\n${links}\n`)
for (const { id, name } of agents) {
  const index = join(root, id, "index.md")
  if (!existsSync(index)) {
    writeFileSync(
      index,
      `---\ntitle: ${JSON.stringify(name)}\n---\n\nNotes and reports from ${name}. Browse this section in the explorer.\n`,
    )
  }
}
