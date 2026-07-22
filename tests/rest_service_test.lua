--- Render-verification suite for the Java REST service archetype: each persistence variant lays
--- out correctly and is fully rendered, and the hollow (None) rendering stays hollow.
---
--- The BEHAVIORAL bar — CRUD through the production image, the platform env contract, health/
--- metrics/structured logs, both name shapes — lives in tests/standards_test.lua (the shared
--- p6m standards suite), fully containerized: docker is the only requirement. The `build_steps`
--- here are gated on a host toolchain and skip cleanly where it's absent.

local SRC = "."

local BASE_ANSWERS = {
  author_name      = "Test Author",
  author_email     = "test@example.com",
  org_name         = "acme",
  solution_name    = "platform",
  prefix_name      = "Example",
  suffix_name      = "Service",
  group_id         = "acme.platform",
  artifactory_host = "acme.jfrog.io",
  image_registry   = "ghcr.io/acme",
}

local function answers_with(extra)
  local out = {}
  for k, v in pairs(BASE_ANSWERS) do out[k] = v end
  for k, v in pairs(extra) do out[k] = v end
  return out
end

-- Files the persistence scaffold adds (relative to the rendered project root). Absent from "None".
local PERSISTENCE_FILES = {
  "example-service-persistence/pom.xml",
  "example-service-persistence/src/main/java/acme/platform/example/persistence/PersistenceConfig.java",
  "example-service-persistence/src/main/java/acme/platform/example/persistence/Item.java",
  "example-service-persistence/src/main/java/acme/platform/example/persistence/ItemRepository.java",
  "example-service-persistence/src/main/resources/db/migration/V1__init.sql",
  "example-service-persistence/src/main/resources/db/migration/V2__create_items.sql",
  "example-service-server/src/main/java/acme/platform/example/server/api/ItemController.java",
  "example-service-server/src/main/resources/application-persistence.yaml",
}

-- Files present in every rendering, persistence or not.
local BASE_FILES = {
  "pom.xml",
  "example-service-bom/pom.xml",
  "example-service-core/pom.xml",
  "example-service-core/src/main/java/acme/platform/example/core/CoreConfig.java",
  "example-service-server/pom.xml",
  "example-service-server/src/main/java/acme/platform/example/server/Application.java",
  "example-service-server/src/main/resources/application.yaml",
  "example-service-integration-tests/pom.xml",
  ".dockerignore",
  ".github/workflows/build.yaml",
}

for _, persistence in ipairs({ "PostgreSQL", "MySQL" }) do
  local label = "java-rest[" .. persistence .. "]"

  local expected = {}
  for _, f in ipairs(BASE_FILES) do expected[#expected + 1] = f end
  for _, f in ipairs(PERSISTENCE_FILES) do expected[#expected + 1] = f end

  archetect.verify{
    name = label,
    source = SRC,
    answers = answers_with{ persistence = persistence },
    project_dir = "example-service",
    expected_files = expected,
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
    requires = { "mvn" },
    build_steps = { "mvn -q -B -DskipTests install" },
  }
end

-- The hollow rendering stays hollow: no persistence module, no scaffold files - and it still builds.
archetect.verify{
  name = "java-rest[None]",
  source = SRC,
  answers = answers_with{ persistence = "None" },
  project_dir = "example-service",
  expected_files = BASE_FILES,
  absent_files = PERSISTENCE_FILES,
  yaml_globs = { ".platform/kubernetes/**/*.yaml" },
  requires = { "mvn" },
  build_steps = { "mvn -q -B -DskipTests install" },
}
