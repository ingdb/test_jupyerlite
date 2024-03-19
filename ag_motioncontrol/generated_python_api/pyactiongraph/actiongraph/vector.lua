-- https://gist.github.com/mebens/1055480
local Vector = {}
Vector.__index = Vector

function Vector.__tostring(v)
    return string.format( "(%8.3f %8.3f %8.3f)" , v.x, v.y, v.z)
end
function Vector.__add(a, b)
    return Vector.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vector.__sub(a, b)
    return Vector.new(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vector.__mul(a, b)
  if type(a) == "number" then
    return Vector.new(b.x * a, b.y * a, b.z * a)
  elseif type(b) == "number" then
    return Vector.new(a.x * b, a.y * b, a.z * b)
  else
    error("bad Vector multiplication")
  end
end

function Vector.__div(a, b)
  if type(b) == "number" then
    return Vector.new(a.x / b, a.y / b, a.z / b)
  else
    error("bad Vector division")
  end
end

function Vector.__eq(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

function Vector.new(x, y, z)
  local r =  { x = x or 0, y = y or 0, z = z or 0,  }
  function r:clone()
    return Vector.new(self.x, self.y, self.z)
  end
  
  function r:unpack()
    return self.x, self.y, self.z
  end
  
  function r:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
  end
  
  function r:lenSq()
    return self.x * self.x + self.y * self.y + self.z * self.z
  end
  
  function r:normalize()
    local len = self:length()
    self.x = self.x / len
    self.y = self.y / len
    self.z = self.z / len
    return self
  end
  
  function r:normalized()
    return self / self:length()
  end
  
  function r:to_table(template)
      local template = template or "%s"
      local ret = {}
      for cn, v in pairs(self) do
          ret[string.format(template, cn)] = v
      end
      return ret
  end
  
  function r:to_array()
      return {self.x, self.y, self.z}
  end
  

  return setmetatable(r, Vector)
end

function Vector.__index(table, key)
  if key == 'x' or key == 'y' or key == 'z' then
    return table[key]
  elseif key == 1 then return table['x']
  elseif key == 2 then return table['y']
  elseif key == 3 then return table['z']
  else
    return nil
  end
end

function Vector.distance(a, b)
  return (b - a):length()
end


setmetatable(Vector, { __call = function(_, ...) return Vector.new(...) end })

return Vector
