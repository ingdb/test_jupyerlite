local P = {}   -- package

-- local ag_utils = require'interpreter.helpers'
-- local log = ag_utils.log
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local json = require'json'
local utils = require("utils")
local Vector = require'vector'

-- local cmd_args = cmd_args

local table = table
local error = error
local globalEnv = _ENV
local _ENV = P

local L = "Left"
local R = "Right"

local ops = {
    ["or"] ={op = {}, op2={prec=100,  assoc=L, ID="OR"}},
    ["and"]={op = {}, op2={prec=101,  assoc=L, ID="AND"}},
    ["="]  ={op = {}, op2={prec=102,   assoc=L, ID="EQUAL"}},
    [">"]  ={op = {}, op2={prec=103,   assoc=L, ID="GREATER"}},
    ["<"]  ={op = {}, op2={prec=103,   assoc=L, ID="LESSER"}},

    ["+"] = {op = {}, op2={prec=104, assoc=L, ID="PLUS"},
                      op1={prec=107, assoc=R, ID="UPLUS"}
        },
    ["-"] = {op = {}, op2={prec=104, assoc=L, ID="MINUS"},
                      op1={prec=107, assoc=R, ID="UMINUS"}
        },
    ["*"] = {op = {}, op2={prec=105, assoc=L, ID="MULT"}},
    ["/"] = {op = {}, op2={prec=105, assoc=L, ID="DIV"}},
    ["%"] = {op = {}, op2={prec=105,  assoc=L, ID="MOD"}},
    
    ["^"] = {op = {}, op2={prec=106, assoc=R, ID="POW"}},

    ["not"]={op = {}, op1={prec=107, assoc=R, ID="NOT"}},


    ["sin"]={fun = {}, f1={prec=150, assoc=R, ID="SIN"}},
    ["cos"]={fun = {}, f1={prec=150, assoc=R, ID="COS"}},
    ["normalized"]={fun = {}, f1={prec=150, assoc=R, ID="NORMALIZED"}},
    ["mag"]      ={fun = {}, f1={prec=150, assoc=R, ID="NORM"}},
    -- ["sq"]        ={fun = {}, f1={prec=150, assoc=R, ID="SQ"}},
    ["sqrt"]      ={fun = {}, f1={prec=150, assoc=R, ID="SQRT"}},
    ["round"]     ={fun = {}, f1={prec=150, assoc=R, ID="ROUND"}},
    ["x"]         ={fun = {}, f1={prec=150, assoc=R, ID="X"}},
    ["y"]         ={fun = {}, f1={prec=150, assoc=R, ID="Y"}},
    ["z"]         ={fun = {}, f1={prec=150, assoc=R, ID="Z"}},

    ["set_x"]         ={fun = {}, f2={prec=150, assoc=R, ID="SETX"}},
    ["set_y"]         ={fun = {}, f2={prec=150, assoc=R, ID="SETY"}},
    ["set_z"]         ={fun = {}, f2={prec=150, assoc=R, ID="SETZ"}},

    ["time"]      ={fun = {}, f0={prec=150, assoc=R, ID="TIME_S"}},
    ["digitalSignal"]={fun = {}, f1={prec=150, assoc=R, ID="DIGITAL_SIG"}},
    ["analogSignal"] ={fun = {}, f1={prec=150, assoc=R, ID="ANALOG_SIG"}},
    ["if"]           ={fun = {}, f3={prec=150, assoc=R, ID="IF"}},
    ["vector"]       ={fun = {}, f3={prec=150, assoc=R, ID="VECTOR"}},
    ["normalNoise"]       ={fun = {}, f2={prec=150, assoc=R, ID="NORMAL_NOISE"}},
    ["formatNumber"]       ={fun = {}, f2={prec=150, assoc=R, ID="FORMAT_NUMBER"}},
    ["get_var"]={fun = {}, f1={prec=150, assoc=R, ID="GETVAR"}},
    ["set_var"]={fun = {}, f1={prec=150, assoc=R, ID="SETVAR"}},

    ["("]       ={open_bracket={}},
    [")"]       ={close_bracket={}},
    [","]       ={function_arg_separator={}}
}

local function lTrimString(s)
    return (s:gsub("^%s*", ""))
end
  
function P.calcPostfixForm(infixInput)
    local rest = infixInput
    local tokens = {}
    while #rest ~= 0 do
      rest = lTrimString(rest)
      if #rest == 0 then break end
      local found = false
      for token, op in pairs(ops) do
        local b, e = rest:find(token, 1, true)
        if b == 1 then
          rest = rest:sub(e+1)
          table.insert( tokens, {token=token, parsed=op})
          found = true
          break
        end
      end
      if found == false then 
      -- trying number
        -- local numberCandidate = rest:match("^-?[0-9]+%.?[0-9]*")
        local numberCandidate = rest:match("^[0-9]+%.?[0-9]*")
        local n = tonumber(numberCandidate)
        if n ~= nil then 
          rest = rest:sub(#numberCandidate + 1)
          found = true
          table.insert( tokens,  {token=numberCandidate, parsed={numeric_value = n}})
        end
      end
      if found == false then 
        -- trying string
        -- utils.print(rest)
          local stringCandidate = rest:match('^"([^"]*)"')
          if stringCandidate ~= nil then
            -- utils.print(stringCandidate)
            rest = rest:sub(#stringCandidate + 3)
            found = true
            table.insert( tokens,  {token='"'..stringCandidate..'"', parsed={string_value = stringCandidate}})
          end
      end
      if found == false then 
        -- trying vector
          local x, y, z = rest:match('^%[%s*(-?[0-9]+%.?[0-9]*)%s*,%s*(-?[0-9]+%.?[0-9]*)%s*,%s*(-?[0-9]+%.?[0-9]*)%s*%]')
          if x ~= nil and y ~=nil and z ~= nil then
            -- utils.print(x, y, z)
            local xn = tonumber(x)
            local yn = tonumber(y)
            local zn = tonumber(z)
            if xn ~= nil and yn ~=nil and zn ~= nil  then
              local b, e = rest:find("]")
              -- utils.print(x, y, z)
              local candidate = rest:sub(1, b)
              rest = rest:sub(b + 1)
              -- utils.print(rest)
              found = true
              table.insert( tokens,  {token='"'..candidate..'"', parsed={vector_value = Vector(xn, yn, zn)}})
            end
          end
      end
      if found == false then 
        -- trying id
        local idCandidate = rest:match("^%.+[a-zA-Z]+[0-9a-zA-Z%._]*")
        if idCandidate~= nil then
          rest = rest:sub(#idCandidate + 1)
          found = true
          table.insert( tokens,  {token=idCandidate, parsed={param_id = idCandidate}})
          -- utils.print(idCandidate)
        end
      end
      if found == false then 
        error("unknown token at the beginning of the string '".. rest.."'")
      end
    end
   
    local out_queue = {}
    local stack = {}
    local ExpectOperand = "ExpectOperand"
    local ExpectOperator = "ExpectOperator"
    local state = ExpectOperand
    for i, token in ipairs(tokens) do
      if token.parsed.numeric_value ~= nil or token.parsed.vector_value ~= nil or token.parsed.string_value ~= nil or token.parsed.param_id ~= nil then
        if state ~= ExpectOperand then error("Expecting operand") end
        table.insert(out_queue, token.parsed)
        state = ExpectOperator
      end

      if token.parsed.fun ~= nil and (tokens[i+1] == nil or (tokens[i+1] ~= nil  and  tokens[i+1].parsed.open_bracket == nil)) then
        if tokens[i+1] then
          utils.print(json.stringify(tokens[i+1].parsed))
        end
        error("Function should be followed by opening bracket")
      end
      if token.parsed.fun ~= nil then
        if state ~= ExpectOperand then error("Expecting operand") end
        state = ExpectOperand
        table.insert(stack, token.parsed)
      end
     
      if token.parsed.op ~= nil then
        local actualOp
        local unary = false
        if token.parsed.op1 ~= nil and token.parsed.op2 ~= nil then
          if tokens[i-1] == nil or tokens[i-1].parsed.open_bracket ~= nil or tokens[i-1].parsed.op ~= nil or tokens[i-1].parsed.function_arg_separator then
            actualOp = "op1"
            unary = true
          else
            actualOp = "op2"
          end
        elseif token.parsed.op1 ~= nil then 
          actualOp = "op1"
          unary = true
        else
          actualOp = "op2"
        end

        if unary == true then
          if state ~= ExpectOperand then error("Expecting operand") end
          state = ExpectOperand
        else
          if state ~= ExpectOperator then error("Expecting operator") end
          state = ExpectOperand
        end

        local toStack = {}
        toStack[actualOp] = token.parsed[actualOp]
        toStack.op = toStack[actualOp]

        while true and unary == false do
          if #stack == 0 then break end
          local stackTopToken = stack[#stack]

          if stackTopToken.open_bracket ~= nil then break end
          
          if stackTopToken.fun == nil then
            if toStack.op.assoc == L and stackTopToken.op.prec < toStack.op.prec then break end
            if toStack.op.assoc == R and stackTopToken.op.prec <= toStack.op.prec then break end
          end
          table.insert(out_queue, table.remove( stack))
        end

       
        table.insert(stack, toStack)
      end
      
      if token.parsed.open_bracket ~= nil then
        if state ~= ExpectOperand then error("Expecting operand") end
        state = ExpectOperand
        table.insert(stack, token.parsed)
      end

      if token.parsed.close_bracket ~= nil then
        -- utils.print("TODO!!!!")
        -- if i < #tokens and state ~= ExpectOperator then error("Expecting operator: ".. i) end
        state = ExpectOperator

        local openingFound = false
        while true do
          if #stack == 0 then break end
          local stackTopToken = stack[#stack]
          if stackTopToken.open_bracket ~= nil then 
            openingFound = true
            table.remove( stack)
            break 
          else
            table.insert(out_queue, table.remove( stack))
          end
        end
        if openingFound == false then
          error("Brackets mismatch")
        end
      end

      if token.parsed.function_arg_separator ~= nil then
        if state ~= ExpectOperator then error("Expecting operator") end
        state = ExpectOperand
        local leftBracketFound = false
        while true do
          if #stack == 0 then break end
          local stackTopToken = stack[#stack]
          if stackTopToken.open_bracket ~= nil then 
            leftBracketFound = true
            break 
          else
            table.insert(out_queue, table.remove( stack))
          end
        end
        if leftBracketFound == false then error("No left bracket") end
      end

    end
    if state ~= ExpectOperator then error("Expecting operator") end
    while true do
      if #stack == 0 then break end
      local tk = table.remove( stack)
      if tk.open_bracket ~= nil then
        error("Brackets mismatch")
      end
      table.insert(out_queue, tk)
    end

    return out_queue
end

-- calcPostfixForm('  sin ( cos (    time ()  )     \t) + 3.14+4 * 2/(1-5.125)^ 2.000 ^ a42 + id1.subid2 - unique_id')
-- calcPostfixForm(cmd_args[1])

return P

-- time sin cos 3.14 + 4 + 2 * 1 5.125 - / 2.0 ^ a42 ^ id1.subid2 + unique_id -
