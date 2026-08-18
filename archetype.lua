local context = Context.new()

-- Identity (S1). One library, one implementation: p6m-identity asks for the project name, the
-- solution slug, and the sample CRUD entity defaulted off the project name. It replaces the
-- author x org x project composition — nothing this archetype renders read the author, and
-- org_name x solution_name were two prompts building one string.
local identity = require("p6m-identity")
identity.prompt(context)

-- Java-specific identity
--
-- Normalize an input into a valid lowercase Java package segment.
local function pkg_segment(value)
    return string.lower((string.gsub(tostring(value), "[^%w]", "")))
end

-- groupId is the shared Maven coordinate for the whole solution. Asked OPTIONAL and derived
-- after: a default computed from `solution_name` cannot be known until that prompt is answered,
-- so an interface probe resolves it against a placeholder and ships that to every client. The
-- help states the derivation instead of interpolating a value into it.
context:prompt_text("Maven Group ID:", "group_id", {
    optional    = true,
    placeholder = "acme.payments",
    help        = "Maven groupId shared across the solution. Leave blank to use the solution slug "
        .. "with its separator swapped (acme-payments -> acme.payments).",
})
if context:get("group_id") == nil or context:get("group_id") == "" then
    context:set("group_id", (string.gsub(context:get("solution-name"), "%-", ".")))
end

context:prompt_text("Artifactory Host:", "artifactory_host", {
    placeholder = "your-org.jfrog.io",
    help = "JFrog Artifactory hostname for Maven repository",
})

-- Derived keys
--
-- root_package is named after the PROJECT, not the entity: it is where this application's code
-- lives, so it must not move when someone answers a different `entity_name`. (It used to be built
-- from `prefix_name`, back when one answer was doing both jobs.)
context:set("root_package", context:get("group_id") .. "." .. pkg_segment(context:get("project-name")))
context:set("root_directory", (string.gsub(context:get("root_package"), "%.", "/")))

-- Service configuration
-- The image registry, asked here rather than by `platform.prompt()` below. It is a deployment
-- fact that belongs beside the solution slug; the manifests library runs last (it needs the
-- resource selections), so leaving it to that call puts the registry dead last in the derived
-- interface — after Source Control — which is exactly where a form should not put it. The library
-- still owns the prompt; `platform.prompt()` finds it answered and skips it.
require("platform-application-manifests").prompt_registry(context)

-- `debug` is not asked: nothing this archetype renders reads `debug_port` — a prompt whose answer
-- nothing consumes cannot justify itself (S1b / E2).
require("ports").prompt(context, { ports = { "service", "management" } })

-- Resources
context:prompt_select("Persistence:", "persistence", {
    "None", "PostgreSQL", "MySQL",
}, { default = "None" })

context:prompt_select("Cache:", "cache", {
    "None", "Redis",
}, { default = "None" })

context:prompt_select("Messaging:", "messaging", {
    "None", "Kafka", "Pulsar",
}, { default = "None" })

if context:get("messaging") ~= "None" then
    context:prompt_select("Messaging Access:", "messaging_access", {
        "produce", "consume",
    }, { default = "produce" })
else
    context:set("messaging_access", "produce")
end

context:set("has_persistence", context:get("persistence") ~= "None")
context:set("has_cache",       context:get("cache")       ~= "None")
context:set("has_messaging",   context:get("messaging")   ~= "None")

context:prompt_multiselect("Object Storage:", "object_storage", {
    "S3", "Azure Blob",
}, { default = {} })

context:set("has_s3",         context:contains("object_storage", "S3"))
context:set("has_azure_blob", context:contains("object_storage", "Azure Blob"))

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

-- SCM
local scm = require("scm")
scm.prompt(context)

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
