return {
    ['$defs'] = {
        EmbeddedParamDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Type = {
                    oneOf = {
                        {const = "Float"},
                        {const = "Integer"},
                        {const = "Vector"},
                        {const = "ByteString"},
                        {const = "Integer"}
                    }
                }
            }
        },
        EmdeddedTypeID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        EmbeddedHardwareDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Parameters = { ['$ref'] = '#/$defs/ConfigurationDeclaration' },
                Description = { ['$ref'] = '#/$defs/DescriptionString'},
            },
        },
        EmbeddedGraphDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Parameters = { ['$ref'] = '#/$defs/ConfigurationDeclaration' },
                Description = { ['$ref'] = '#/$defs/DescriptionString'},
            },
        },
    },
    additionalProperties = false,
    minProperties = 1,
    properties = {
        Hardware = { 
            type = 'object',
            minProperties = 1,
            keyObjectPatternProperties = {
                {
                    keyPattern = { ['$ref'] = '#/$defs/EmdeddedTypeID' },
                    valuePattern =  {['$ref'] = '#/$defs/EmbeddedHardwareDeclaration'}
                }
            }
        },
        Graphs = {
            type = 'object',
            minProperties = 1,
            keyObjectPatternProperties = {
                {
                    keyPattern = { ['$ref'] = '#/$defs/EmdeddedTypeID' },
                    valuePattern =  {['$ref'] = '#/$defs/EmbeddedGraphDeclaration'}
                }
            } 
        }
    }
}