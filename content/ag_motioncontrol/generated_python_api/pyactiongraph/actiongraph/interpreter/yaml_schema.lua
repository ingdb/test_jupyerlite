local actiongraphSchema_1 = {
    ['$defs'] = {

        ExportedGraphTypeName = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        ExportedHardwareTypeName = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        ExportedConfigurationTypeName = {
            type = 'string',
            pattern =  [[^\w+$]]
        },


        ImportSourcePackageName = {
            type = 'string',
            pattern =  [[^.*[\w\.]+$]]
        },

        ExportSourcePackageName = {
            type = 'string',
            pattern =  [[^.*[\w\.]+$]]
        },
        ExportSection = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Configurations = {
                    type = 'object',
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ExportSourcePackageName' },
                            valuePattern =  {
                                type =  'array',
                                items = {['$ref'] = '#/$defs/ExportedConfigurationTypeName'}
                            }
                        }
                    },
                    additionalProperties = false,
                    minProperties = 1
                },
                Hardware = {
                    type = 'object',
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ExportSourcePackageName' },
                            valuePattern =  {
                                type =  'array',
                                items = {['$ref'] = '#/$defs/ExportedHardwareTypeName'}
                            }
                        }
                    },
                    additionalProperties = false,
                    minProperties = 1
                },
                Graphs = {
                    type = 'object',
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ExportSourcePackageName' },
                            valuePattern =  {
                                type =  'array',
                                items = {['$ref'] = '#/$defs/ExportedGraphTypeName'}
                            }
                        }
                    },
                    additionalProperties = false,
                    minProperties = 1
                }
            }
        },

        ExternConfigurationTypeName = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        ExternHardwareTypeName = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        ExternGraphTypeName = {
            type = 'string',
            pattern =  [[^\w+$]]
        },

        ImportSection = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Configurations = {
                    type = 'object',
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ImportSourcePackageName' },
                            valuePattern =  {
                                type =  'array',
                                items = {['$ref'] = '#/$defs/ExternConfigurationTypeName'}
                            }
                        }
                    },
                    additionalProperties = false,
                    minProperties = 1
                },
                Hardware = {
                    type = 'object',
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ImportSourcePackageName' },
                            valuePattern =  {
                                type =  'array',
                                items = {['$ref'] = '#/$defs/ExternHardwareTypeName'}
                            }
                        }
                    },
                    additionalProperties = false,
                    minProperties = 1
                },
                Graphs = {
                    type = 'object',
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ImportSourcePackageName' },
                            valuePattern =  {
                                type =  'array',
                                items = {['$ref'] = '#/$defs/ExternGraphTypeName'}
                            }
                        }
                    },
                    additionalProperties = false,
                    minProperties = 1
                }
            }
        },
        DescriptionString = {
            type = 'string'
        },
        ParameterInstanceFPConstant = {
            oneOf = {
                { type = 'number' },
                {
                    type = 'object',
                    additionalProperties = false,
                    required = {'Type'},
                    properties = {
                        Type = { const = 'Float'},
                        Value = { type = 'number' },
                        Mutable = { type = 'boolean'},
                        Internal = { type = 'boolean'},
                        Description = { ['$ref'] = '#/$defs/DescriptionString'}
                    }
                }
            }
        },
        ParameterInstanceIntConstant = {
            oneOf = {
                { type = 'integer' },
                { type = 'boolean' },
                {
                    type = 'object',
                    additionalProperties = false,
                    required = {'Type'},
                    properties = {
                        Type = { const = 'Integer'},
                        Value = { type = 'number' },
                        Mutable = { type = 'boolean'},
                        Internal = { type = 'boolean'},
                        Description = { ['$ref'] = '#/$defs/DescriptionString'}
                    }
                }
            }
        },
        ParameterInstanceVectorConstant = {
            oneOf = {
                {
                    type = 'array',
                    items = { type = 'number'},
                    minItems = 3,
                    maxItems = 3
                },
                {
                    type = 'object',
                    additionalProperties = false,
                    required = {'Type'},
                    properties = {
                        Type = { const = 'Vector'},
                        Value = {
                            type = 'array',
                            items = { type = 'number'},
                            minItems = 3,
                            maxItems = 3
                        },
                        Mutable = { type = 'boolean'},
                        Internal = { type = 'boolean'},
                        Description = { ['$ref'] = '#/$defs/DescriptionString'}
                    }
                }
            }
        },
        ParameterInstanceExpression = {
            type = 'string',
            pattern = [[^\s*=.+]]
        },
        ParameterInstanceNamedEvent = {
            type = 'string',
            pattern = [[^\s*<.*>\s*$]]
        },
        ParameterInstanceByteStringConstant = {
            oneOf = {
                { type = 'string', pattern = [[^\s*/.*/\s*$]] },
                {
                    type = 'object',
                    additionalProperties = false,
                    required = {'Type'},
                    properties = {
                        Type = { const = 'ByteString'},
                        Value = { type = 'string' },
                        Mutable = { type = 'boolean'},
                        Internal = { type = 'boolean'},
                        Description = { ['$ref'] = '#/$defs/DescriptionString'}
                    }
                }
            }
        },
        ParameterInstanceMutable = {
            allOf = {
                {
                    type = 'object',
                    required = {'Mutable'},
                    properties = {
                        Mutable = { const = true },
                    }
                }, {
                    oneOf = {
                        {
                            allOf = {
                                { ['$ref'] = '#/$defs/ParameterInstanceFPConstant'},
                                { ['not'] = {['$ref'] = '#/$defs/ParameterInstanceIntConstant'} },
                            }
                        },
                        { ['$ref'] = '#/$defs/ParameterInstanceIntConstant' },
                        { ['$ref'] = '#/$defs/ParameterInstanceVectorConstant' },
                        { ['$ref'] = '#/$defs/ParameterInstanceByteStringConstant' },
                    }
                }
            }
        },
        ParameterInstanceImmutable = {
            allOf = {
                {
                    ['not'] = {
                        type = 'object',
                        required = {'Mutable'},
                        properties = {
                            Mutable = { const = true },
                        }
                    }
                }, {
                    oneOf = {
                        {
                            allOf = {
                                { ['$ref'] = '#/$defs/ParameterInstanceFPConstant'},
                                { ['not'] = {['$ref'] = '#/$defs/ParameterInstanceIntConstant'} },
                            }
                        },
                        { ['$ref'] = '#/$defs/ParameterInstanceIntConstant' },
                        { ['$ref'] = '#/$defs/ParameterInstanceVectorConstant' },
                        { ['$ref'] = '#/$defs/ParameterInstanceByteStringConstant' },
                        { ['$ref'] = '#/$defs/ParameterInstanceExpression' },
                        { ['$ref'] = '#/$defs/ParameterInstanceNamedEvent' },
                        -- { ['$ref'] = '#/$defs/HardwareModuleInstance' },
                        -- { ['$ref'] = '#/$defs/GraphInstance' }
                    }
                }
            }
        },
        ParameterInstance = {
            oneOf = {
                { ['$ref'] = '#/$defs/ParameterInstanceImmutable' },
                { ['$ref'] = '#/$defs/ParameterInstanceMutable' },
            }
        },
        ParameterAlias = {
            allOf = {
                {
                    type = 'string',
                    pattern = [[^(?:\.|(?:\.\.)*)(?:\w+(?:\.\w+)*)?$]]
                },
                { ['not'] = {['$ref'] = '#/$defs/ParameterInstance'} },
            }
        },
        PureAliasParameter = {
            type = 'null'
        },
        AssignedParameter = {
            oneOf = {
                { ['$ref'] = '#/$defs/ParameterAlias' },
                { ['$ref'] = '#/$defs/ParameterInstance' },
                { ['$ref'] = '#/$defs/PureAliasParameter' }
            }
        },
        BatchParameterAssignTarget = {
            const = "*"
        },
        AssignTargetParameterID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
      
        ConfigurationAssignment = {
            type = 'object',
            keyObjectPatternProperties = {
                {
                    keyPattern = { ['$ref'] = '#/$defs/AssignTargetParameterID' },
                    valuePattern =  {['$ref'] = '#/$defs/AssignedParameter'}
                },
                {
                    keyPattern = { ['$ref'] = '#/$defs/BatchParameterAssignTarget' },
                    valuePattern =  {['$ref'] = '#/$defs/ParameterAlias'}
                }
            },
            minProperties = 1,
            additionalProperties = false
        },

        DeclaredParameterID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        ParameterDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/ParameterAlias' },
                { ['$ref'] = '#/$defs/ParameterInstance' },
                { ['$ref'] = '#/$defs/PureAliasParameter' }
            }
        },
        ConfigurationDeclaration = {
            type = 'object',
            keyObjectPatternProperties = {
                {
                    keyPattern = { ['$ref'] = '#/$defs/DeclaredParameterID' },
                    valuePattern =  { ['$ref'] = '#/$defs/ParameterDeclaration' }
                }
            },
            -- minProperties = 1,
            additionalProperties = false
        },
        ChildHardwareModuleInstanceID = {
            type = 'string',
            pattern = [[^\w+$]]
        },
        HardwareNewTypeDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Autostart = {type = "boolean"},
                Parameters = { ['$ref'] = '#/$defs/ConfigurationDeclaration' },
                Modules = {
                    type = 'object',
                    additionalProperties = false,
                    minProperties = 1,
                    keyObjectPatternProperties = { 
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ChildHardwareModuleInstanceID' },
                            valuePattern =  {['$ref'] = '#/$defs/HardwareModuleInstance'}
                        }
                    }
                },
                Main = { ['$ref'] = '#/$defs/ChildHardwareModuleInstanceID' },
                Description = { ['$ref'] = '#/$defs/DescriptionString'},
                Components = { ['$ref'] = '#/$defs/TypesDeclaration' }
            },
            required = {'Modules'}
        },
        HardwareTypeID = {
            type = 'string',
            pattern = [[^\w+$]]
        },
        HardwareDerivedTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/HardwareTypeID' },
                {
                    type = 'object',
                    required = {'Type'},
                    additionalProperties = false,
                    properties = {
                        Type = { ['$ref'] = '#/$defs/HardwareTypeDeclaration' },
                        Parameters = { ['$ref'] = '#/$defs/ConfigurationAssignment' },
                        Autostart = {type = 'boolean'}
                    }
                }
            }
        },
        HardwareTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/HardwareNewTypeDeclaration' },
                { ['$ref'] = '#/$defs/HardwareDerivedTypeDeclaration' }
            }
        },
        HardwareModuleInstance = {
            oneOf = {
                { ['$ref'] = '#/$defs/HardwareTypeDeclaration' },
                {
                    type = 'object',
                    additionalProperties = false,
                    minProperties = 1,
                    maxProperties = 1,
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/HardwareTypeID' },
                            valuePattern =  {['$ref'] = '#/$defs/ConfigurationAssignment'}
                        }
                    }
                }
            }
        },

        ChildGraphNodeInstanceID = {
            type = 'string',
            pattern = [[^\w+$]]
        },
    
        GraphNewSequentialTypeDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Sequential = { type = 'array', minItems = 1, items = { ['$ref'] = '#/$defs/GraphInstance' } },
                Connections = { ['$ref'] = '#/$defs/ConnectionsInstance' },
                Parameters = { ['$ref'] = '#/$defs/ConfigurationDeclaration' },
                IgnoreUnhandledEvent = {type = 'boolean'},
                Script = { ['$ref'] = '#/$defs/ScriptFilePath' },
                Description = { ['$ref'] = '#/$defs/DescriptionString'},
                Components = { ['$ref'] = '#/$defs/TypesDeclaration' },
                StateTransitionEvents = { ['$ref'] = '#/$defs/StateTransitionEventsDeclaration' },
                StateControlSlots =  { ['$ref'] = '#/$defs/StateControlSlotsDeclaration' },
            },
            required = {'Sequential'}
        },
        GraphNewParallelTypeDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Parallel = { type = 'array', minItems = 1, items = { ['$ref'] = '#/$defs/GraphInstance' }  },
                Connections = { ['$ref'] = '#/$defs/ConnectionsInstance' },
                Parameters = { ['$ref'] = '#/$defs/ConfigurationDeclaration' },
                IgnoreUnhandledEvent = {type = 'boolean'},
                Script = { ['$ref'] = '#/$defs/ScriptFilePath' },
                Description = { ['$ref'] = '#/$defs/DescriptionString'},
                Components = { ['$ref'] = '#/$defs/TypesDeclaration' },
                StateTransitionEvents = { ['$ref'] = '#/$defs/StateTransitionEventsDeclaration' },
                StateControlSlots =  { ['$ref'] = '#/$defs/StateControlSlotsDeclaration' },
            },
            required = {'Parallel'}
        },
        GraphNewGenericTypeDeclaration = {
            type = 'object',
            additionalProperties = false,
            properties = {
                Nodes = { 
                    type = 'object',
                    additionalProperties = false,
                    minProperties = 1,
                    keyObjectPatternProperties = { 
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ChildGraphNodeInstanceID' },
                            valuePattern =  {['$ref'] = '#/$defs/GraphInstance'}
                        }
                    } 
                },
                Connections = { ['$ref'] = '#/$defs/ConnectionsInstance' },
                Parameters = { ['$ref'] = '#/$defs/ConfigurationDeclaration' },
                IgnoreUnhandledEvent = {type = 'boolean'},
                Script = { ['$ref'] = '#/$defs/ScriptFilePath' },
                Description = { ['$ref'] = '#/$defs/DescriptionString'},
                Components = { ['$ref'] = '#/$defs/TypesDeclaration' },
                StateTransitionEvents = { ['$ref'] = '#/$defs/StateTransitionEventsDeclaration' },
                StateControlSlots =  { ['$ref'] = '#/$defs/StateControlSlotsDeclaration' },
            },
            required = {'Nodes', 'Connections'}
        },
        GraphNewTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/GraphNewSequentialTypeDeclaration' },
                { ['$ref'] = '#/$defs/GraphNewParallelTypeDeclaration'  },
                { ['$ref'] = '#/$defs/GraphNewGenericTypeDeclaration' }
            }
        },
        SlotAlias = {
            type = 'string',
            pattern = [[^(?:\.|(?:\.\.))\w+(?:\.\w+)*$]]
        },
        SlotAliasList = {
            oneOf = {
                {
                    ['$ref'] = '#/$defs/SlotAlias'
                }
                ,
                {
                    type = 'array',
                    items = {['$ref'] = '#/$defs/SlotAlias'},
                    minItems = 1
                }
            }
        },
        ConnectionTriggeringEvent = {
            type = 'string',
            pattern = [[^(?:\.|(?:\.\.))\w+(?:\.\w+)*$]]
        },
        ConnectionEventsAll = {
            type = 'object',
            additionalProperties = false,
            required = { "All"},
            properties = {
                All = {type = 'array', minItems = 1, items = { ['$ref'] = '#/$defs/ConnectionTriggeringEvent' } }
            }
        },
        ConnectionEventsAny = {
            type = 'object',
            additionalProperties = false,
            required = { "Any"},
            properties = {
                Any = {type = 'array', minItems = 1, items = { ['$ref'] = '#/$defs/ConnectionTriggeringEvent' } }
            }
        },
        EventsCombination = {
            oneOf = {
                { ['$ref'] = '#/$defs/ConnectionTriggeringEvent' },
                { ['$ref'] = '#/$defs/ConnectionEventsAll' },
                { ['$ref'] = '#/$defs/ConnectionEventsAny' },
            }
        },
        ConnectionsInstance = {
            type = 'object',
            additionalProperties = false,
            keyObjectPatternProperties = {
                {
                    keyPattern = { ['$ref'] = '#/$defs/EventsCombination' },
                    valuePattern =  {['$ref'] = '#/$defs/SlotAliasList'}
                }
            },
            minProperties = 1
        },
        StateTransitionEventsDeclaration = {
            type = 'object',
            additionalProperties = false,
            keyObjectPatternProperties = {
                {
                    keyPattern = {
                        type = 'string',
                        pattern =  [[^\w+$]]
                    },
                    valuePattern =  {type = 'null'}
                }
            },
            minProperties = 1
        },
        StateControlSlotsDeclaration = {
            type = 'object',
            additionalProperties = false,
            keyObjectPatternProperties = {
                {
                    keyPattern = {
                        type = 'string',
                        pattern =  [[^\w+$]]
                    },
                    valuePattern =  {type = 'null'}
                }
            },
            minProperties = 1
        },
        GraphTypeID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        GraphDerivedTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/GraphTypeID' },
                {
                    type = 'object',
                    required = {'Type'},
                    additionalProperties = false,
                    properties = {
                        Type = { ['$ref'] = '#/$defs/GraphTypeDeclaration' },
                        Parameters = { ['$ref'] = '#/$defs/ConfigurationAssignment' },
                        IgnoreUnhandledEvent = {type = 'boolean'},
                        Script = { ['$ref'] = '#/$defs/ScriptFilePath' }
                    }
                }
            }
        },
        GraphTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/GraphNewTypeDeclaration' },
                { ['$ref'] = '#/$defs/GraphDerivedTypeDeclaration' }
            }
        },
        GraphInstance = {
            oneOf = {
                { ['$ref'] = '#/$defs/GraphTypeDeclaration' },
                {
                    type = 'object',
                    additionalProperties = false,
                    minProperties = 1,
                    maxProperties = 1,
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/GraphTypeID' },
                            valuePattern =  {['$ref'] = '#/$defs/ConfigurationAssignment'}
                        }
                    }
                }
            }
        },

        ConfigurationNewTypeDeclaration = {
            ['$ref'] = '#/$defs/ConfigurationDeclaration'
        },
        ConfigurationDerivedTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/ConfigurationTypeID' },
                {
                    type = 'object',
                    required = {'Type'},
                    additionalProperties = false,
                    properties = {
                        Type = { ['$ref'] = '#/$defs/ConfigurationTypeDeclaration' },
                        Parameters = { ['$ref'] = '#/$defs/ConfigurationAssignment' }
                    }
                }
            }
        },
        ConfigurationTypeDeclaration = {
            oneOf = {
                { ['$ref'] = '#/$defs/ConfigurationNewTypeDeclaration' },
                { ['$ref'] = '#/$defs/ConfigurationDerivedTypeDeclaration' }
            }
        },
        ConfigurationTypeID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
        ConfigurationInstance ={ ['$ref'] = '#/$defs/ConfigurationTypeDeclaration' },

        ScriptFilePath = {
            type = 'string',
            minLength = 1
        },
        ModuleDefinedGraphTypeID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
     
        ModuleDefinedHardwareTypeID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },
      
        ModuleDefinedConfigurationTypeID = {
            type = 'string',
            pattern =  [[^\w+$]]
        },

        TypesDeclaration = {
            type = 'object',
            additionalProperties = false,
            minProperties = 1,
            properties = {
                Hardware = { 
                    type = 'object',
                    minProperties = 1,
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ModuleDefinedHardwareTypeID' },
                            valuePattern =  {['$ref'] = '#/$defs/HardwareTypeDeclaration'}
                        }
                    }
                },
                Graphs = {
                    type = 'object',
                    minProperties = 1,
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ModuleDefinedGraphTypeID' },
                            valuePattern =  {['$ref'] = '#/$defs/GraphTypeDeclaration'}
                        }
                    } 
                },
                Configurations = {  
                    type = 'object',
                    minProperties = 1,
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ModuleDefinedConfigurationTypeID' },
                            valuePattern =  {['$ref'] = '#/$defs/ConfigurationTypeDeclaration'}
                        }
                    } 
                }
            }
        },


        RobotSerial = {
            type = 'string',
            minLength = 8,
            maxLength = 8
        },
        RobotConfig = {
            type = 'object',
            properties = {                
                Configurations = { 
                    type = 'object',
                    minProperties = 1,
                    keyObjectPatternProperties = {
                        {
                            keyPattern = { ['$ref'] = '#/$defs/ModuleDefinedConfigurationTypeID' },
                            valuePattern =  {['$ref'] = '#/$defs/ConfigurationInstance'}
                        }
                    }
                },
                Hardware = {
                    ['$ref'] = '#/$defs/HardwareModuleInstance'
                },
                Graph = {
                    ['$ref'] = '#/$defs/GraphInstance'
                },
                Script = { ['$ref'] = '#/$defs/ScriptFilePath' },
                Serial =  { ['$ref'] = '#/$defs/RobotSerial' },
            },
            required = {'Graph'},
            additionalProperties = false
        },
        RobotID = {
            type = 'string',
            pattern = [[^\w+$]]
        },
       
        ActionGraphVersionValue = { type = 'number' },
        Module = {
            type = 'object',
            properties = {
                ActionGraphVersion = { ['$ref'] = '#/$defs/ActionGraphVersionValue' },
                Import = {
                    ['$ref'] = '#/$defs/ImportSection'
                },
                Components = { ['$ref'] = '#/$defs/TypesDeclaration' },
                Robots =  { 
                    type = 'object',
                    additionalProperties = false,
                    minProperties = 1,
                    keyObjectPatternProperties = { 
                        {
                            keyPattern = { ['$ref'] = '#/$defs/RobotID' },
                            valuePattern =  {['$ref'] = '#/$defs/RobotConfig'}
                        }
                    }
                },
                Script = { ['$ref'] = '#/$defs/ScriptFilePath' }
            },
            required = {'ActionGraphVersion'},
            additionalProperties = false
        },
        PackageManifest = {
            type = 'object',
            properties = {
                ActionGraphVersion = { ['$ref'] = '#/$defs/ActionGraphVersionValue' },
                Export = {
                    ['$ref'] = '#/$defs/ExportSection'
                },
                Description = { ['$ref'] = '#/$defs/DescriptionString' }
            },
            required = {'ActionGraphVersion', 'Export'},
            additionalProperties = false
        },
        ActiongraphSourceFile = {
            oneOf = {
                { ['$ref'] = '#/$defs/Module' },
                { ['$ref'] = '#/$defs/PackageManifest' } ,
            }
        }
    },

    ['$ref'] = '#/$defs/ActiongraphSourceFile'
}


return actiongraphSchema_1