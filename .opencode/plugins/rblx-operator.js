/**
 * RBLX Operator — opencode plugin.
 *
 * Loaded automatically from .opencode/plugins/ when opencode runs in this
 * repo. Gives the agent four custom tools for shipping Roblox games:
 *
 *   rblx_verify   — run the engine's Luau + JS validation gate
 *   rblx_compile  — derive + compile a game from a prompt (offline, zero keys)
 *   rblx_build    — rojo build the current spec into a .rbxl place
 *   rblx_open     — open a built .rbxl in Roblox Studio
 *
 * Also logs a small marker when the agent drives the pipeline so sessions show
 * the engine working (via client.app.log).
 */

import { tool } from "@opencode-ai/plugin"

const run = async (cmd, args, cwd) => {
  const { execFile } = await import("node:child_process")
  const { promisify } = await import("node:util")
  const { resolve } = await import("node:path")
  const execFileP = promisify(execFile)
  const root = resolve(cwd || process.cwd())
  const [bin, ...rest] = cmd.split(" ")
  try {
    const { stdout, stderr } = await execFileP(bin, rest.concat(args), {
      cwd: root,
      maxBuffer: 32 * 1024 * 1024,
    })
    return (stderr ? stderr + "\n" : "") + (stdout || "(no output)")
  } catch (err) {
    return `ERROR: ${err.message}\n${err.stdout || ""}${err.stderr || ""}`
  }
}

export const RblxOperatorPlugin = async ({ directory, client }) => {
  const cwd = directory
  if (client && client.app && client.app.log) {
    await client.app.log({
      body: {
        service: "rblx-operator",
        level: "info",
        message: "RBLX Operator plugin loaded — engine tools armed.",
      },
    })
  }
  return {
    tool: {
      rblx_verify: tool({
        description:
          "Run the RBLX Operator engine validation gate (Luau --!strict + JS syntax). Use before finishing any game design.",
        args: {},
        async execute() {
          return run("node", ["pipeline/bridge.js", "verify"], cwd)
        },
      }),
      rblx_compile: tool({
        description:
          "Compile a complete Roblox game from a prompt via the RBLX Operator engine (offline derivation, zero API keys). Produces games/<slug>/spec.json and regenerates src/shared/config.luau.",
        args: {
          idea: tool.schema.string().describe("The game idea, e.g. 'a dark zombie survival in a cursed mall, 10 waves'"),
        },
        async execute(args) {
          return run("node", ["pipeline/bridge.js", "newgame", "--offline", args.idea], cwd)
        },
      }),
      rblx_build: tool({
        description:
          "Build the current game spec into a Roblox place file with Rojo. Requires Rojo installed (https://rojo.space).",
        args: {
          output: tool.schema
            .string()
            .optional()
            .describe("Output .rbxl file name (default: RBLXOperator.rbxl)"),
        },
        async execute(args) {
          const out = args.output || "RBLXOperator.rbxl"
          return run("rojo", ["build", "default.project.json", "-o", out], cwd)
        },
      }),
      rblx_open: tool({
        description: "Open a built .rbxl file in Roblox Studio so the game can be playtested.",
        args: {
          file: tool.schema
            .string()
            .optional()
            .describe(".rbxl file name (default: RBLXOperator.rbxl; must look like a game file)"),
        },
        async execute(args) {
          // Never hand an LLM-supplied string to cmd.exe — validate it first.
          const file = args.file || "RBLXOperator.rbxl"
          if (!/^[\w.-]+\.rbxl$/.test(file)) {
            return `ERROR: refused — "${file}" is not a plain .rbxl file name. Use e.g. RBLXOperator.rbxl or a file you built.`
          }
          return run("cmd", ["/c", "start", "", file], cwd)
        },
      }),
    },
  }
}
