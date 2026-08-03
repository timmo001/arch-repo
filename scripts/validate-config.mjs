import { readFileSync } from "node:fs";

const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));
const repository = readJson("config/repository.json");
const packages = readJson("config/packages.json");
const lifecycle = readJson("config/r2-lifecycle.json");

if (
  repository.schemaVersion !== 1 ||
  repository.repository !== "timmo" ||
  repository.hostname !== "packages.timmo.dev" ||
  repository.retainedVersions !== 2 ||
  JSON.stringify(repository.architectures) !== '["x86_64"]'
) {
  throw new Error("Invalid repository configuration");
}

const packageName = /^[a-z0-9@_+][a-z0-9@._+-]*$/;
const sourceRepository = /^timmo001\/[A-Za-z0-9._-]+$/;
for (const [name, config] of Object.entries(packages.packages ?? {})) {
  if (
    !packageName.test(name) ||
    !sourceRepository.test(config.repository) ||
    JSON.stringify(config.architectures) !== '["x86_64"]'
  ) {
    throw new Error(`Invalid package configuration: ${name}`);
  }
}

const lifecycleCondition = lifecycle.rules?.[0]?.abortMultipartUploadsTransition?.condition;
if (lifecycleCondition?.type !== "Age" || lifecycleCondition.maxAge !== 86400) {
  throw new Error("Invalid incomplete multipart upload lifecycle rule");
}
