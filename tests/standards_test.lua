--- The p6m platform standards, held against this archetype (prova-p6m-standards docs/standards.md).
--- One suite, parameterized by the SAME answers the archetype renders from — and now literally the
--- same object: `p6m.spec{}` builds the identity, the render answers and the SQL oracle together,
--- so this file cannot answer the archetype one thing and assert another. That was not a
--- hypothetical: before the shape harness, this suite asserted against a hardcoded `items` table
--- while golang's and rust's asserted `{prefix_name}s`, for one standard that says the entity is
--- name-derived — and both passed.
---
--- Container-first (S8): the SUT is the archetype's own .platform/docker/prd image on a topology
--- network — docker is the only requirement, no JDK or Maven on the host.

local p6m = require("p6m")
local postgres = require("postgres")
local mysql = require("mysql")

-- Two variants cover both axes cheaply: name shape (single vs multi-word — casing bugs only show
-- on the second) paired with persistence backend.
local VARIANTS = {
  { project = "customer-service", entity = "customer", persistence = "PostgreSQL", db = postgres,
    placeholder = "$1" },
  { project = "user-details-service", entity = "user-details", persistence = "MySQL", db = mysql,
    placeholder = "?" },
}

for _, v in ipairs(VARIANTS) do
  local spec = p6m.spec{
    language = "java", shape = "full", transport = "rest",
    project = v.project, entity = v.entity, solution = "acme-platform",
    persistence = v.persistence, registry = "ghcr.io/acme",
    answers = { group_id = "acme.platform", artifactory_host = "acme.jfrog.io" },
  }

  local project = p6m.render(spec)

  local sut = prova.topology(spec.label .. ":sut", function(ctx)
    local root = ctx:use(project):dir(spec.project_dir)
    return p6m.sut(ctx, { root = root.path, id = spec.id, transport = "rest", db = v.db })
  end)

  prova.group(spec.label, { requires = { "docker" }, tags = { "standards" } }, function(g)
    p6m.standards.api(g, sut, {
      persisted = function(t, name, count)
        local svc = t:use(sut)
        -- The table comes from the spec, not from this file: S2's entity is name-derived, and a
        -- hardcoded table name here could never fail against a hardcoded table name there.
        t:expect(
          svc.db.client:query_value(
            "SELECT count(*) FROM " .. spec.table_name .. " WHERE display_name = " .. v.placeholder,
            { name }),
          "rows in the database"
        ):equals(count)
      end,
    })
    p6m.standards.runtime(g, sut)

    g:test("Flyway migrated the SUT's " .. v.persistence .. " database", function(t)
      local svc = t:use(sut)
      -- The schema-history table exists in the very container the SUT is wired to only because
      -- the booted service ran its migrations there.
      t:expect(svc.db.client:query_value("SELECT count(*) FROM flyway_schema_history"),
        "applied migrations"):gte(1)
    end)
  end)
end

-- S1b: the archetype's own prompt surface is the declared interface — a defaults=false render
-- proves nothing beyond the declared key is REQUIRED, and the composed catalog proves no vestigial
-- DEFAULTED prompt survives. Hermetic; no docker.
prova.group("java-rest: the archetype itself", function(g)
  local spec = p6m.spec{
    language = "java", shape = "full", transport = "rest",
    project = "billing-service", entity = "billing", solution = "acme-platform",
    answers = { group_id = "acme.platform", artifactory_host = "acme.jfrog.io" },
  }
  p6m.standards.prompt_surface(g, spec, {
    resources = {
      "java-resource-postgresql", "java-resource-mysql", "java-resource-redis",
      "java-resource-kafka", "java-resource-pulsar", "java-resource-s3",
      "java-resource-azure-blob",
    },
  })
end)

-- E7's released-tag bar, as the `p6m-pin` reminder: DUE while the manifest pins `dev` (the
-- YP6M-3372 staging window), silent again once the pin returns to a released tag. Heed it
-- (`prova --heed=p6m-pin`) when the window closes.
p6m.pin_reminder()
