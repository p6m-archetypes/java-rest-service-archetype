--- Acceptance suite for the Java REST service archetype: renders each persistence variant, verifies
--- the layout, builds the Maven reactor, boots the Spring Boot service against a real database
--- container, and proves the service came up wired to that database. This suite defines the
--- archetype's acceptance bar - its job is to fill the gaps and keep them filled.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova
--- requires docker + mvn + java (JDK 21); skips cleanly without them.
---
--- NOTE: the persistence flavors now carry the standard CRUD surface (p6m standards S2 - see
--- tests/standards_test.lua for the containerized standards bar). This suite keeps the host-level
--- acceptance: layout, reactor build, boot against BOTH database backends (the standards suite
--- exercises PostgreSQL only), Flyway migrations applied, and a POST -> row round-trip.

local postgres = require("postgres")
local mysql    = require("mysql")

local SRC = "."
-- Repackaging the server module yields this runnable Spring Boot jar (see the service fixture).
local BOOT_JAR = "example-service-server/target/example-service-server-1.0.0-SNAPSHOT.jar"

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

-- Files the persistence module adds (relative to the rendered project root). Absent from "None".
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
  ".github/workflows/build.yaml",
}

-- Build the whole reactor. The server pom binds spring-boot:repackage to `package` (the rendered
-- Dockerfiles run the module jar with `java -jar`), so a single `install` already leaves the
-- executable boot jar we run - a single process prova can manage and kill cleanly (unlike a
-- forking `spring-boot:run`).
local function build(dir)
  shell.run("mvn -q -B -DskipTests install", { cwd = dir, timeout = "900s", check = true })
end

-- One entry per DB-backed rendering variant. `db` is the container plugin; the count SQL carries the
-- backend's identifier quoting.
local VARIANTS = {
  { persistence = "PostgreSQL", db = postgres, count_all = [[SELECT count(*) FROM flyway_schema_history]] },
  { persistence = "MySQL",      db = mysql,    count_all = "SELECT count(*) FROM flyway_schema_history" },
}

for _, v in ipairs(VARIANTS) do
  local label = "java-rest[" .. v.persistence .. "]"

  -- a) render - one fixture per variant, shared by verify and the boot fixture.
  local project = prova.fixture(label .. ":project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = v.persistence },
      destination = ctx:tempdir(),
      defaults = true,
    }
  end)

  -- b) verify - layout + manifests against that rendering (the boot below proves the build).
  local expected = {}
  for _, f in ipairs(BASE_FILES) do expected[#expected + 1] = f end
  for _, f in ipairs(PERSISTENCE_FILES) do expected[#expected + 1] = f end
  archetect.verify(project, {
    name = label,
    project_dir = "example-service",
    expected_files = expected,
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
  })

  -- c) black-box - provision the database, build, boot the service wired to it.
  local service = prova.fixture(label .. ":service", Scope.File, function(ctx)
    local root = ctx:use(project):dir("example-service")
    local db = v.db.container(ctx)

    build(root.path)

    local port, mgmt = net.free_port(), net.free_port()
    ctx:manage(shell.spawn("java -jar " .. BOOT_JAR, {
      cwd = root.path,
      env = {
        -- The platform env contract, nothing more: application.yaml binds the ports and
        -- auto-includes the persistence profile, so no SPRING_PROFILES_ACTIVE is needed.
        SERVER_PORT     = port,
        MANAGEMENT_PORT = mgmt,
        DB_HOST         = db.host,
        DB_PORT         = db.port,
        DB_DBNAME       = "prova",
        DB_USERNAME     = "prova",
        DB_PASSWORD     = "prova",
      },
    }))

    -- Readiness answering proves the whole chain: the app only reports UP after Flyway migrated the
    -- database and the datasource health check passed against the container.
    local readiness = "http://127.0.0.1:" .. mgmt .. "/health/readiness"
    http.wait_for(readiness, { status = 200, timeout = "180s", every = "1s" })
    return { readiness = readiness, base = "http://127.0.0.1:" .. port, db = db.client }
  end)

  prova.group(label .. " boots against " .. v.persistence, { requires = { "docker", "mvn", "java" } }, function(g)
    g:test("readiness reports UP", function(t)
      local svc = t:use(service)
      local res = http.get(svc.readiness)
      t:expect(res.status):equals(200)
      t:expect(res:json().status):equals("UP")
    end)

    g:test("Flyway migrated the real " .. v.persistence .. " database", function(t)
      local svc = t:use(service)
      -- Query the very database the service is wired to: the schema-history table exists only
      -- because the booted service ran its migrations against this container.
      t:expect(svc.db:query_value(v.count_all), "applied migrations"):gte(1)
    end)

    g:test("the standard API persists to the real " .. v.persistence .. " database", function(t)
      local svc = t:use(service)
      local created = http.post(svc.base .. "/api/v1/examples", { json = { displayName = "widget" } })
      t:expect(created.status):equals(201)
      local body = created:json()
      t:expect(body.displayName):equals("widget")
      -- The row landed in the container the service is wired to, not an in-memory stand-in.
      t:expect(
        svc.db:query_value("SELECT count(*) FROM items WHERE display_name = 'widget'"),
        "rows in the database"
      ):equals(1)
      t:expect(http.get(svc.base .. "/api/v1/examples/" .. body.id):json().displayName):equals("widget")
    end)
  end)
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
