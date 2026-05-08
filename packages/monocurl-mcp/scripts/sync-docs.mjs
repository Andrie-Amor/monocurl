import { existsSync, lstatSync, mkdirSync, rmSync, symlinkSync, unlinkSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(here, "..");
const repoRoot = resolve(packageRoot, "../..");

function relink(path, target, type) {
  const stat = lstatSync(path, { throwIfNoEntry: false });

  if (stat?.isSymbolicLink()) {
    unlinkSync(path);
  } else if (existsSync(path)) {
    rmSync(path, { recursive: true, force: true });
  }

  symlinkSync(target, path, type);
}

mkdirSync(resolve(packageRoot, "docs"), { recursive: true });
relink(resolve(packageRoot, "docs/std"), "../../../assets/std/std", "dir");
relink(resolve(packageRoot, "icon.png"), "../../assets/img/monocurl.png", "file");
