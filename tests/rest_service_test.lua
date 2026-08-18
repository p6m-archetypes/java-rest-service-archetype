--- Render-verification suite for the Java REST service archetype: each persistence variant lays
--- out correctly and is fully rendered, and the hollow (None) rendering stays hollow.
---
--- Every rendering comes from `p6m.spec{}` + `p6m.render` — the shape harness — so the paths this
--- file expects are BUILT from the same identity the archetype was answered with, never spelled by
--- hand. A hand-spelled path list is how `example-service/.../Item.java` outlived the entity it was
--- named for.
---
--- The BEHAVIORAL bar — CRUD through the production image, the platform env contract, health/
--- metrics/structured logs, both name shapes — lives in tests/standards_test.lua. Compile coverage
--- is containerized: the standards SUT image builds compile the persistence variants, and the
--- hollow rendering is proven compilable by building its production Dockerfile here — no host
--- toolchain is ever required.

local p6m = require("p6m")

local LANG_ANSWERS = { group_id = "acme.platform", artifactory_host = "acme.jfrog.io" }

local function spec_for(persistence)
  return p6m.spec{
    language = "java", shape = "full", transport = "rest",
    project = "example-service", entity = "example", solution = "acme-platform",
    persistence = persistence, registry = "ghcr.io/acme", answers = LANG_ANSWERS,
  }
end

-- The java module layout, derived from the spec. `root_directory` mirrors the archetype's own
-- derivation (group_id + the project's package segment) — stated once here rather than in a path
-- literal per file.
local function paths(s)
  local p = s.project_dir
  local pkg = "acme/platform/" .. s.id.project_snake:gsub("_", "")
  return {
    base = {
      "pom.xml",
      p .. "-bom/pom.xml",
      p .. "-core/pom.xml",
      p .. "-core/src/main/java/" .. pkg .. "/core/CoreConfig.java",
      p .. "-server/pom.xml",
      p .. "-server/src/main/java/" .. pkg .. "/server/Application.java",
      p .. "-server/src/main/resources/application.yaml",
      p .. "-integration-tests/pom.xml",
      ".dockerignore",
      ".github/workflows/build.yaml",
    },
    persistence = {
      p .. "-persistence/pom.xml",
      -- NOTE the directory is `root_directory` (group_id + the project segment) while these files
      -- DECLARE `{{ group_id }}.persistence` — the two disagree fleet-wide. javac tolerates it
      -- because Maven passes an explicit file list, and PersistenceConfig pins its @EntityScan to
      -- the declared package, so it works. Asserting the DIRECTORY is what this check is about.
      p .. "-persistence/src/main/java/" .. pkg .. "/persistence/PersistenceConfig.java",
      p .. "-persistence/src/main/java/" .. pkg .. "/persistence/" .. s.id.EntityName .. ".java",
      p .. "-persistence/src/main/java/" .. pkg .. "/persistence/" .. s.id.EntityName .. "Repository.java",
      p .. "-persistence/src/main/resources/db/migration/V1__init.sql",
      p .. "-persistence/src/main/resources/db/migration/V2__create_" .. s.table_name .. ".sql",
      p .. "-server/src/main/java/" .. pkg .. "/server/api/" .. s.id.EntityName .. "Controller.java",
      p .. "-server/src/main/resources/application-persistence.yaml",
    },
  }
end

for _, persistence in ipairs({ "PostgreSQL", "MySQL" }) do
  local s = spec_for(persistence)
  local f = paths(s)

  local expected = {}
  for _, x in ipairs(f.base) do expected[#expected + 1] = x end
  for _, x in ipairs(f.persistence) do expected[#expected + 1] = x end

  archetect.verify{
    name = s.label,
    source = ".",
    answers = s.answers,
    project_dir = s.project_dir,
    expected_files = expected,
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
  }
end

-- The hollow rendering stays hollow: no persistence module, no scaffold files.
local none = spec_for("None")
local none_paths = paths(none)
local none_project = p6m.render(none)

archetect.verify(none_project, {
  name = none.label,
  project_dir = none.project_dir,
  expected_files = none_paths.base,
  absent_files = none_paths.persistence,
  yaml_globs = { ".platform/kubernetes/**/*.yaml" },
})

-- Containerized compile proof for the hollow rendering: the persistence variants are compiled by
-- the standards suite's SUT image builds; None never boots there, so prove it compiles by
-- building its production Dockerfile (build success = it compiles; no boot needed).
prova.group(none.label .. ":image", { requires = { "docker" } }, function(g)
  g:test("production image builds (compiles the hollow rendering)", function(t)
    local root = t:use(none_project):dir(none.project_dir)
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
prova.group(none.label .. ":ci", { requires = { "docker" }, tags = { "standards" } }, function(g)
  p6m.standards.ci_parity(g, none_project, {
    stack = "java",
    project_dir = none.project_dir,
    name = "java-rest",
  })
end)
