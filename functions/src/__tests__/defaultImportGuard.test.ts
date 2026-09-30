/**
 * No default imports under `src/`.
 *
 * `tsconfig.json` sets `allowSyntheticDefaultImports` because nodemailer 10's
 * bundled declarations default-import Node builtins (#85). Without
 * `esModuleInterop`, that flag also lets *our* code write `import os from "os"`,
 * which type-checks and compiles to `os_1.default.hostname()`, and
 * `os_1.default` is undefined at runtime. tsc used to reject that import; this
 * test rejects it now. Use `import * as os from "os"` or a named import.
 *
 * `import type X from` is allowed: it is erased from the emitted JS.
 */

import * as fs from "fs";
import * as path from "path";

const SRC = path.join(__dirname, "..");
const DEFAULT_IMPORT = /^\s*import\s+(?!type\s)[A-Za-z_$][\w$]*\s*(,|from\b)/;

it("no source under src/ uses a default import", () => {
  const offenders = fs
    .readdirSync(SRC, { recursive: true, encoding: "utf8" })
    .filter((file) => file.endsWith(".ts"))
    .flatMap((file) =>
      fs
        .readFileSync(path.join(SRC, file), "utf8")
        .split("\n")
        .flatMap((line, i) =>
          DEFAULT_IMPORT.test(line) ? [`${file}:${i + 1}: ${line.trim()}`] : []
        )
    );

  expect(offenders).toEqual([]);
});
