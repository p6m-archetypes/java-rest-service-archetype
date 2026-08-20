local context = Context.new()

-- The prompt surface is laid out in PAGES and SECTIONS. These carry the author's grouping intent —
-- the one thing a derived interface cannot infer from the script — to every renderer: a wizard step
-- in Ybor Studio, a titled heading in the terminal, a block comment in an answers template.
--
-- Built for the HYBRID drive: a client describes with the answers it has, renders the first page
-- that still has children, collects them, and describes again. Two consequences shape what is
-- written here:
--
--   * Keys are PINNED, never derived from a title, because a wizard routes on them and pages
--     appear and disappear between rounds. Titles are display text; keys are identity.
--   * A prompt that depends on an earlier answer sits in the SAME page as what it depends on
--     (Messaging Access under Messaging, repository details under Source Control). The page simply
--     comes back with new fields and the client stays on that step — progressive disclosure,
--     rather than a step that vanishes and reappears elsewhere.
--
-- The vocabulary is the fleet's, not this archetype's: every p6m archetype uses the same page and
-- section keys, so a form reads identically whatever the language or shape. An archetype omits a
-- section it has no prompts for; it does not invent one.
local identity = require("p6m-identity")

context:page({ title = "Project", key = "project",
               help = "What this service is called, and the domain it models." }, function(ctx)
    identity.prompt_project(ctx)

    -- The deployment coordinates, grouped deliberately: this is exactly the set Ybor Studio
    -- supplies per solution, so hiding them later is "this section came back empty" rather than a
    -- re-grouping exercise.
    ctx:section({ title = "Platform", key = "platform",
                  help = "Where this service deploys and publishes." }, function(ctx)
        identity.prompt_solution(ctx)

        -- The registry is asked here rather than by `platform.prompt()` below: the manifests
        -- library runs last (it needs the resource selections), which would put the registry dead
        -- last in the derived interface. The library still owns the prompt definition.
        require("platform-application-manifests").prompt_registry(ctx)

        -- Asked OPTIONAL and derived after: an envelope computed from `solution_name` cannot be
        -- known until that prompt is answered, so a probe would resolve it against a placeholder.
        ctx:prompt_text("Maven Group ID:", "group_id", {
            optional    = true,
            placeholder = "acme.payments",
            help        = "Maven groupId shared across the solution. Leave blank to use the "
                .. "solution slug with its separator swapped (acme-payments -> acme.payments).",
        })
        if ctx:get("group_id") == nil or ctx:get("group_id") == "" then
            ctx:set("group_id", (string.gsub(ctx:get("solution-name"), "%-", ".")))
        end

        -- OPTIONAL, deliberately. This was the one prompt a first-time user could not answer:
        -- a registry hostname nobody outside the owning org knows, with no default, blocking the
        -- form. A scaffold has no business requiring a package registry to exist — so when it is
        -- absent the pom simply omits its distributionManagement, and `mvn deploy` is a thing you
        -- configure when you have somewhere to deploy to. Ybor Studio supplies it per solution
        -- (see p6m-catalog's README), which is where a company-specific hostname belongs.
        ctx:prompt_text("Artifactory Host:", "artifactory_host", {
            optional    = true,
            placeholder = "your-org.jfrog.io",
            help        = "JFrog Artifactory hostname for the Maven repository. Leave blank to "
                .. "omit publishing configuration from the pom.",
        })
    end)

    ctx:section({ title = "Service", key = "service",
                  help = "The ports this service listens on." }, function(ctx)
        -- `debug` is not asked: nothing this archetype renders reads `debug_port` (S1b / E2).
        require("ports").prompt(ctx, { ports = { "service", "management" } })
    end)
end)

context:page({ title = "Resources", key = "resources",
               help = "Platform-provisioned backing services. The platform provisions each one and "
                   .. "injects its connection settings; no credentials are asked for here." }, function(ctx)
    ctx:section({ title = "Persistence", key = "persistence" }, function(ctx)
        ctx:prompt_select("Persistence:", "persistence", { "None", "PostgreSQL", "MySQL" },
            { default = "None" })
    end)

    ctx:section({ title = "Cache", key = "cache" }, function(ctx)
        ctx:prompt_select("Cache:", "cache", { "None", "Redis" }, { default = "None" })
    end)

    ctx:section({ title = "Messaging", key = "messaging" }, function(ctx)
        ctx:prompt_select("Messaging:", "messaging", { "None", "Kafka", "Pulsar" },
            { default = "None" })
        -- Intra-page dependency, deliberately: choosing a broker brings this page back with one
        -- more field rather than sending the client to a different step.
        if ctx:get("messaging") ~= "None" then
            ctx:prompt_select("Messaging Access:", "messaging_access", { "produce", "consume" },
                { default = "produce" })
        else
            ctx:set("messaging_access", "produce")
        end
    end)

    ctx:section({ title = "Object Storage", key = "object_storage" }, function(ctx)
        ctx:prompt_multiselect("Object Storage:", "object_storage", { "S3", "Azure Blob" },
            { default = {} })
    end)
end)

-- Derived keys. Not prompts, so they sit outside the layout.
--
-- Normalize an input into a valid lowercase Java package segment.
local function pkg_segment(value)
    return string.lower((string.gsub(tostring(value), "[^%w]", "")))
end

-- root_package is named after the PROJECT, not the entity: it is where this application's code
-- lives, so it must not move when someone answers a different `entity_name`.
context:set("root_package", context:get("group_id") .. "." .. pkg_segment(context:get("project-name")))
context:set("root_directory", (string.gsub(context:get("root_package"), "%.", "/")))

context:set("has_persistence", context:get("persistence") ~= "None")
context:set("has_cache",       context:get("cache")       ~= "None")
context:set("has_messaging",   context:get("messaging")   ~= "None")
context:set("has_s3",          context:contains("object_storage", "S3"))
context:set("has_azure_blob",  context:contains("object_storage", "Azure Blob"))

-- EditorConfig + gitignore
local editor_config = require("editor-config")
editor_config.prompt(context, {
    languages     = { "Java", "YAML", "Markdown" },
    gitattributes = true,
})

local gitignore = require("gitignore")
gitignore.prompt(context, {
    ignores = { "Java", "Claude", "IDEA", "VSCode", "macOS" },
})

-- SCM — its own page: publishing is a decision about delivery, not about the service. The
-- repository details it reveals are intra-page, so choosing a provider keeps the client here.
local scm = require("scm")
context:page({ title = "Source Control", key = "source_control",
               help = "Optionally create and publish the repository." }, function(ctx)
    scm.prompt(ctx)
end)

if archetype.switches.is_enabled("debug-context") then
    log.info(archetype.description .. " Context:")
    output.print(format.yaml(context))
end

-- Render base workspace
directory.render("contents/base", context)

-- Resource libraries
local dest = { destination = context:get("project-name") }

if context:get("persistence") == "PostgreSQL" then
    require("java-resource-postgresql").render(context, dest)
elseif context:get("persistence") == "MySQL" then
    require("java-resource-mysql").render(context, dest)
end

-- The standard CRUD surface (p6m standards S2) rides on the persistence module: entity +
-- repository land in the module the resource library just rendered; the controller in the server.
if context:get("has_persistence") then
    directory.render("contents/crud", context)
end

if context:get("has_cache") then
    require("java-resource-redis").render(context, dest)
end

if context:get("messaging") == "Kafka" then
    require("java-resource-kafka").render(context, dest)
elseif context:get("messaging") == "Pulsar" then
    require("java-resource-pulsar").render(context, dest)
end

if context:get("has_s3") then
    require("java-resource-s3").render(context, dest)
end

if context:get("has_azure_blob") then
    require("java-resource-azure-blob").render(context, dest)
end

-- CI workflows
local ci = require("java-ci")
ci.render(context, dest)

-- Platform manifests
context:set("protocol", "REST")
local platform = require("platform-application-manifests")
platform.prompt(context)
platform.finalize(context, dest)

-- EditorConfig, gitignore, SCM finalize
editor_config.finalize(context, dest)
gitignore.finalize(context, dest)
scm.finalize(context)

-- Archive (zip / tarball switches for Ybor Studio)
require("archiver").finalize(context)

return context
