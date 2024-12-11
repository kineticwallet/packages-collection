--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local replicatedStoragePackages = ReplicatedStorage:WaitForChild("Packages")
local sharedPackages = replicatedStoragePackages.Shared

return require(sharedPackages.Signal)
