--- Render-verification suite for the Java REST service archetype: each persistence variant lays
--- out correctly and is fully rendered, and the hollow (None) rendering stays hollow.
---
--- The BEHAVIORAL bar — CRUD through the production image, the platform env contract, health/
--- metrics/structured logs, both name shapes — lives in tests/standards_test.lua (the shared
--- p6m standards suite), fully containerized: docker is the only requirement. Compile coverage
--- is containerized too: the standards SUT image builds compile the persistence variants, and
--- the hollow rendering is proven compilable by building its production Dockerfile here — no
--- host toolchain is ever required.

local p6m = require("p6m")

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
  }
end

-- The hollow rendering stays hollow: no persistence module, no scaffold files.
local none_project = prova.fixture("java-rest[None]:project", Scope.File, function(ctx)
  return archetect.render{
    source = SRC,
    answers = answers_with{ persistence = "None" },
    destination = ctx:tempdir(),
    defaults = true,
  }
end)

archetect.verify(none_project, {
  name = "java-rest[None]",
  project_dir = "example-service",
  expected_files = BASE_FILES,
  absent_files = PERSISTENCE_FILES,
  yaml_globs = { ".platform/kubernetes/**/*.yaml" },
})

-- Containerized compile proof for the hollow rendering: the persistence variants are compiled by
-- the standards suite's SUT image builds; None never boots there, so prove it compiles by
-- building its production Dockerfile (build success = it compiles; no boot needed).
prova.group("java-rest[None]:image", { requires = { "docker" } }, function(g)
  g:test("production image builds (compiles the hollow rendering)", function(t)
    local root = t:use(none_project):dir("example-service")
    local image = docker.build{
      context = root.path,
      dockerfile = ".platform/docker/prd/Dockerfile",
    }
    t:expect(image, "built image ref"):never():is_empty()
  end)
end)

-- CI parity (S10): the rendered project's own Build workflow path — the build.yaml's single
-- 'mvn verify --no-transfer-progress' on a fresh clone, in the toolchain image. The Dockerfile
-- and CI are two independent build paths; S10 holds the second. The hollow render suffices:
-- resource variants change dependencies, not the command path.
prova.group("java-rest[None]:ci", { requires = { "docker" }, tags = { "standards" } }, function(g)
  p6m.standards.ci_parity(g, none_project, {
    stack = "java",
    project_dir = "example-service",
    name = "java-rest",
  })
end)
