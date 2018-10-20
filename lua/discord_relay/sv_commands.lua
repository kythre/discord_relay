DiscordRelay.CmdPrefix = "^[%$%.!/]"
DiscordRelay.AdminRoles = { -- TODO: Use permission system instead
	["491349829419663371"] = true, -- a
}

function DiscordRelay.IsMemberAdmin(member)
	for roleId, _ in next, DiscordRelay.AdminRoles do
		if DiscordRelay.MemberHasRoleID(member, roleId) then
			return true
		end
	end
	return false
end

local function doEval(func)
	local msg = {}
	local __G = {}
	for i, v in pairs(_G) do __G[i] = v end

	local env = setmetatable(__G, getmetatable(easylua.EnvMeta))
	setfenv(func, env)

	local ret = { pcall(func) }
	local ok = ret[1]
	table.remove(ret, 1)
	if not ok then
		msg = {
			{
				title = "Lua Error:",
				description = tostring(ret[1]),
				color = DiscordRelay.HexColors.Red
			}
		}
		DiscordRelay.SendToDiscordRaw(nil, nil, msg)
		return
	end
	if ret[1] then
		for k, v in next, ret do
			-- TODO: pretty print tables
			ret[k] = tostring(v):gsub("`", "\\`")
		end
		local res = "```lua\n" .. table.concat(ret, "\t") .. "```"
		if #res >= 2000 then
			res = res:sub(1, 1970) .. "```[...]\noutput truncated"
		end
		msg = {
			{
				title = "Result:",
				description = res,
				color = DiscordRelay.HexColors.Purple
			}
		}
	else
		msg = ":white_check_mark:"
	end
	DiscordRelay.SendToDiscordRaw(nil, nil, msg)
end
DiscordRelay.Commands = {
	status = function(msg)
		local time = CurTime()
		local uptime = string.format(":arrows_clockwise: **Uptime**: %.2d:%.2d:%.2d",
			math.floor(CurTime() / 60 / 60), -- hours
			math.floor(CurTime() / 60 % 60), -- minutes
			math.floor(CurTime() % 60) -- seconds
		)
		local players = {}
		for _, ply in next, player.GetAll() do
			players[#players + 1] = ply:Nick()
		end
		players = table.concat(players, ", ")
		DiscordRelay.SendToDiscordRaw(nil, nil, {
			{
				author = {
					name = GetHostName(),
					url = "https://re-dream.org/join",
					icon_url = "https://re-dream.org/media/redream-logo.png"
				},
				description = uptime .. " - :map: **Map**: `" .. game.GetMap() .. "`",
				fields = {
					{
						name = "Players: " .. player.GetCount() .. " / " .. game.MaxPlayers(),
						value = players:Trim() ~= "" and [[```]] .. players .. [[```]] or "It's lonely in here."
					}
				},
				color = DiscordRelay.HexColors.LightBlue
			}
		})
	end,
	help = function()
		local helpText = {}
		for cmd, _ in next, DiscordRelay.Commands do
			helpText[#helpText + 1] = cmd
		end
		helpText = table.concat(helpText, ", ")
		DiscordRelay.SendToDiscordRaw(nil, nil, {
			{
				title = "Available commands:",
				description = "```" .. helpText .. "```",
				color = DiscordRelay.HexColors.Purple
			}
		})
	end,
	rcon = function(msg, line)
		local admin = DiscordRelay.IsMemberAdmin(msg.author)
		if not admin then
			DiscordRelay.SendToDiscordRaw(nil, nil, {
				{
					title = "No access!",
					color = DiscordRelay.HexColors.Red
				}
			})
			return
		end

		cmd(line)
		DiscordRelay.SendToDiscordRaw(nil, nil, ":white_check_mark:")
	end,
}