import { spawn } from "node:child_process";

const supportedTargets = ["avr"] as const;

export type SupportedTarget = (typeof supportedTargets)[number];

if (typeof require !== "undefined" && require.main === module) {
  const extraArgs = process.argv.slice(2);
  if (extraArgs.length > 0) {
    console.log("Extra arguments:", extraArgs);
  }
  if (process.env["ACTIONS_RUNTIME_TOKEN"]) {
    console.log("Using GitHub Actions cache for Docker buildx");
    extraArgs.push(
      "--cache-to=type=gha,mode=max,scope=gas",
      "--cache-from=type=gha,scope=gas"
    );
  }
  const ret = spawn("docker", [
    "buildx",
    "build",
    "--progress=plain",
    "--build-arg=BRANCH=binutils-2_45-branch",
    `--build-arg=TARGET=${supportedTargets.join(",")}`,
    `--output=${process.cwd()}/build`,
    ...extraArgs,
    `${process.cwd()}/build`,
  ]);
  ret.stdout.pipe(process.stdout);
  ret.stderr.pipe(process.stderr);
  ret.on("exit", (code) => {
    process.exit(code ?? 0);
  });
}
