-- Deliberately recognizable stub. Not encryption; tests only.
return {seal = function(plaintext) return "TEST-SEALED:" .. plaintext:reverse() end}
