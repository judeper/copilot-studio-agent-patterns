/**
 * Patches pcf-scripts ManifestSchema.json to allow the <platform-library> element.
 *
 * pcf-scripts ^1 does not include "platform-library" in its manifest validation
 * schema, but virtual PCF controls require it to declare shared platform libraries
 * (React, Fluent). This postinstall script adds the missing property definition
 * so that `pcf-scripts build` succeeds without validation errors.
 *
 * This is a known gap in pcf-scripts -- the Power Platform runtime accepts
 * platform-library elements, but the local build tooling schema lags behind.
 */
const fs = require("fs");
const path = require("path");

const schemaPath = path.join(
    __dirname,
    "..",
    "node_modules",
    "pcf-scripts",
    "ManifestSchema.json"
);

if (!fs.existsSync(schemaPath)) {
    console.warn("patch-manifest-schema: ManifestSchema.json not found, skipping patch");
    process.exit(0);
}

const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));
const control = schema.definitions.control;

// Only patch if platform-library is not already defined
if (control.properties["platform-library"]) {
    process.exit(0);
}

// Add platform-library as an allowed property on the control element
control.properties["platform-library"] = {
    type: "array",
    items: { $ref: "#/definitions/platform-library" },
};

// Add the platform-library definition if not present
if (!schema.definitions["platform-library"]) {
    schema.definitions["platform-library"] = {
        type: "object",
        properties: {
            $: {
                type: "object",
                properties: {
                    name: { type: "string" },
                    version: { type: "string" },
                },
                required: ["name", "version"],
                additionalProperties: false,
            },
        },
        required: ["$"],
        additionalProperties: false,
    };
}

fs.writeFileSync(schemaPath, JSON.stringify(schema, null, 4), "utf8");
