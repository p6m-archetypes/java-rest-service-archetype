--- Acceptance suite for the Java REST service archetype: renders each persistence variant, verifies
--- the layout, builds the Maven reactor, boots the Spring Boot service against a real database
--- container, and proves the service came up wired to that database. This suite defines the
--- archetype's acceptance bar - its job is to fill the gaps and keep them filled.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova
--- requires docker + mvn + java (JDK 21); skips cleanly without them.
---
--- NOTE (why this matters): the archetype today is a SCAFFOLD - the service exposes only actuator
--- health/readiness and no application routes, and its persistence module ships a single empty Flyway
--- migration. prova *booting* the service against a real database is exactly what proves "renders +
--- compiles" is backed by a service that actually starts and connects. As the archetype grows real
--- REST CRUD over the persistence layer, the assertions below graduate from "readiness is UP / the
--- schema history was written" to real persisted state (POST -> row -> GET).

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
  "example-service-persistence/src/main/resources/db/migration/V1__init.sql",
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

-- Build the whole reactor, then repackage the server into a runnable boot jar. The archetype's
-- spring-boot-maven-plugin has no repackage execution (images are built with jib), so `install`
-- alone yields a thin jar; a second package+repackage (siblings resolved from the reactor we just
-- installed, `-nsu` to skip remote SNAPSHOT lookups) produces the executable jar we boot with
-- `java -jar` - a single process prova can manage and kill cleanly (unlike a forking
-- `spring-boot:run`). Not `-o`: offline can't resolve the `spring-boot` plugin prefix on a cold
-- CI cache, since `install` never downloads that plugin.
local function build(dir)
  shell.run("mvn -q -B -DskipTests install", { cwd = dir, timeout = "900s", check = true })
  shell.run("mvn -q -B -nsu -pl example-service-server -DskipTests package spring-boot:repackage",
    { cwd = dir, timeout = "900s", check = true })
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
        -- application.yaml binds these from the environment.
        SERVER_PORT            = port,
        MANAGEMENT_PORT        = mgmt,
        -- application-persistence.yaml carries the datasource; the profile activates it.
        SPRING_PROFILES_ACTIVE = "persistence",
        DB_HOST                = db.host,
        DB_PORT                = db.port,
        DB_DBNAME              = "prova",
        DB_USERNAME            = "prova",
        DB_PASSWORD            = "prova",
      },
    }))

    -- Readiness answering proves the whole chain: the app only reports UP after Flyway migrated the
    -- database and the datasource health check passed against the container.
    local readiness = "http://127.0.0.1:" .. mgmt .. "/health/readiness"
    http.wait_for(readiness, { status = 200, timeout = "180s", every = "1s" })
    return { readiness = readiness, db = db.client }
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
