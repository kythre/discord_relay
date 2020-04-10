if not DiscordRelay then
	Error("Woah, we couldn't find ourselves a config file! If this happens, you should reinstall.")
end

DiscordRelay.NextRunTime = DiscordRelay.NextRunTime or SysTime()
DiscordRelay.FileLocations = DiscordRelay.FileLocations or {}
DiscordRelay.FileLocations.ReceivedMessages = "discord_relay/received_messages.txt"
DiscordRelay.Self = DiscordRelay.Self or nil

if not file.IsDir("discord_relay/", "DATA") then
	file.CreateDir("discord_relay")
end

for k, v in pairs(DiscordRelay.FileLocations) do
	if not file.Exists(v, "DATA") then
		file.Write(v, util.TableToJSON({}))
	end

	DiscordRelay[k] = util.JSONToTable(file.Read(v, "DATA") or "") or {}
end

http.Loaded = http.Loaded and http.Loaded or false
local function checkHTTP()
	http.Post("https://google.com", {}, function()
		http.Loaded = true
	end, function()
		http.Loaded = true
	end)
end

if not http.Loaded then
	timer.Create("HTTPLoadedCheck", 3, 0, function()
		local ok, err = pcall(function()
			if not http.Loaded then
				checkHTTP()
			else
				hook.Run("HTTPLoaded")
				timer.Remove("HTTPLoadedCheck")
			end
		end)
		if not ok then
			ErrorNoHalt("what the FUCK")
			ErrorNoHalt(err)
		end
	end)
end

-- Thanks Author. for this bypass. Need to know when HTTP loads so we can gather some info about the bot and shit
hook.Add("HTTPLoaded", "GetSelf", function()
	HTTP({
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
		end,
		success = function(code, body, headers)
			DiscordRelay.Self = util.JSONToTable(body)
		end,
		url = "https://discordapp.com/api/users/@me"
	})
end)

local errcodes = {
	[50001] = "Your bot cannot read the channel! Please ensure the bot has 'Read Messages' permission for the channel.",
	[50010] = "Your bot hasn't got an account! Please go back and make one!"
}

function DiscordRelay.VerifyMessageSuccess(code, body, headers)
	body = util.JSONToTable(body)
	
	PrintTable(headers)

	if body then
		if body.code then
			ErrorNoHalt("[ERROR] Discord returned error code " .. body.code .. ": " .. body.message .. "\n")

			if DiscordRelay.DEBUG_MODE then
				print("HTML Code", "Headers")
				print(code, headers)
			end

			if errcodes[body.code] then
				print(errcodes[body.code])
			end

			return false
		else
			return true
		end
	else
		return false
	end
end

DiscordRelay.HexColors = {
	Red = 0xC73232,
	LightBlue = 0x3295C7,
	Green = 0x32C643,
	Purple = 0xA369C7,
	Teal = 0x32C79A
}

function DiscordRelay.SendToDiscordRaw(username, avatar, message)
	local t_post = {
		username = username,
		avatar_url = avatar,
	}
	if istable(message) then
		t_post.embeds = message
	else
		t_post.content = message
	end

	local body = util.TableToJSON(t_post, true)
	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error in sending raw message to discord: " .. err .. "\n")
		end,
		success = DiscordRelay.VerifyMessageSuccess,
		method = "POST",
		url = DiscordRelay.WebhookURL,
		parameters = t_post,
		body = body,
		headers = {
			["User-Agent"] = "myBotThing (https://some.url, v0.1)",
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len() or "0",
		},
		type = "application/json"
	}

	HTTP(t_struct)
end

include("discord_relay/sv_api.lua")
include("discord_relay/sv_commands.lua")

-- From Discord
util.AddNetworkString("DiscordRelay_MessageReceived")

function DiscordRelay.HandleChat(code, body, headers)
	if not body then return end

	if body == nil then
		MsgC(Color(255, 255, 0), "Non fatal error: No messages retrieved from discord, perhaps a connectivity error is to blame?\n")

		return
	end

	if not DiscordRelay.VerifyMessageSuccess(code, body, headers) then return end
	body = util.JSONToTable(body)

	if body.message == "You are being rate limited." then
		DiscordRelay.NextRunTime = SysTime() + body.retry_after
		MsgC(Color(255, 0, 0), "Discord error: You are being rate limited. The relay will not check for messages again for another " .. body.retry_after .. " seconds.\n")
		ErrorNoHalt("Discord Rate Limiting Detected. Message retrieval will be disabled for approximately " .. body.retry_after .. " seconds.")
		DiscordRelay.SendToDiscordRaw(nil, nil, "The bot is being rate limited! Players on the server will not see your messages for another " .. body.retry_after .. " seconds.")

		return
	end

	for i = DiscordRelay.MaxMessages, 1, -1 do
		local gotitalready = false
		if not body[i] then continue end
		if body[i].webhook_id then continue end

		for k, v in pairs(DiscordRelay.ReceivedMessages) do
			if (v.id == body[i].id) then
				gotitalready = true
			end
		end

		if body[i].embeds then
			for k, embed in next, body[i].embeds do
				if embed.title and embed.description then
					body[i].content = embed.title .. " - " .. embed.description
				end
			end
		end
		if string.len(body[i].content) > 256 then
			if not gotitalready then
				DiscordRelay.SendToDiscordRaw(nil, nil, "Sorry " .. body[i].author.username .. ", but that message was too long and wasn't relayed.")
			end

			table.insert(DiscordRelay.ReceivedMessages, {
				id = body[i].id,
				content = body[i].content,
				author = {
					id = body[i].author.id,
					username = body[i].author.username
				}
			})

			file.Write(DiscordRelay.FileLocations.ReceivedMessages, util.TableToJSON(DiscordRelay.ReceivedMessages))
			continue
		end
		if body[i].mentions then
			for k, v in next, body[i].mentions do
				local tofind = "(<@!?" .. v.id .. ">)"
				local username = DiscordRelay.GetMemberNick(v)
				local toreplace = "@" .. username
				body[i].content = string.gsub(body[i].content, tofind, toreplace)
			end
		end
		if body[i].attachments then
			for _, attachment in next, body[i].attachments do
				body[i].content = attachment.url .. " " .. body[i].content
			end
		end
		body[i].content = body[i].content:gsub("<(:[^%s.]*:)%d+>", "%1") -- custom emoji fix

		if gotitalready == false then
			MsgC(COLOR_DISCORD, "[Discord] ", COLOR_USERNAME, body[i].author.username, COLOR_COLON, ": ", COLOR_MESSAGE, body[i].content, "\n")
			local msg = body[i].content
			local prefix = msg:match(DiscordRelay.CmdPrefix)

			if prefix then
				local cmd = msg:Split(" ")
				cmd = cmd[1]:sub(prefix:len() + 1):lower()

				local args = msg:sub(prefix:len() + 1 + cmd:len() + 1)

				local callback = DiscordRelay.Commands[cmd:lower()]
				if callback then
					callback(body[i], args)
				end
			end

			local username = DiscordRelay.GetMemberNick(body[i].author)
			net.Start("DiscordRelay_MessageReceived")
				net.WriteString(username)
				net.WriteString(msg)
			net.Broadcast()

			table.insert(DiscordRelay.ReceivedMessages, {
				id = body[i].id,
				content = body[i].content,
				author = {
					id = body[i].author.id,
					username = body[i].author.username
				}
			})

			file.Write(DiscordRelay.FileLocations.ReceivedMessages, util.TableToJSON(DiscordRelay.ReceivedMessages, true))
		end
	end
end

function DiscordRelay.GetMessages()
	if SysTime() < DiscordRelay.NextRunTime then return end

	if not DiscordRelay.BotToken or DiscordRelay.BotToken == "" then
		Error("Invalid Bot Token!")
	end

	if not DiscordRelay.DiscordChannelID or DiscordRelay.DiscordChannelID == "" then
		Error("Invalid Channel ID.")
	end

	local t_struct = {
		failed = function(err)
			MsgC(Color(255, 0, 0), "HTTP error: " .. err .. "\n")
		end,
		success = DiscordRelay.HandleChat,
		url = "https://discordapp.com/api/channels/" .. DiscordRelay.DiscordChannelID .. "/messages",
		method = "GET",
		headers = {
			["User-Agent"] = "myBotThing (https://some.url, v0.1)",
			["Authorization"] = "Bot " .. DiscordRelay.BotToken
		}
	}

	HTTP(t_struct)
end

hook.Add("Think", "Discord_Check_Messages", function()
	if SysTime() >= DiscordRelay.NextRunTime then
		DiscordRelay.GetMessages()
		DiscordRelay.NextRunTime = SysTime() + DiscordRelay.MessageDelay
	end
end)

timer.Create("Discord_GuildInfo", 10, 0, function()
	DiscordRelay.GetMembers()
	DiscordRelay.GetGuild()
end)

-- To Discord
hook.Add("PlayerDeath", "Discord_Player_Death", function(victim, inflictor, attacker)
	local deathmessage = ""
	local messagedaddy

	if attacker:IsVehicle() and IsValid(attacker:GetDriver()) then
		attacker = attacker:GetDriver()
	end
	
	if attacker:IsPlayer() then
		messagedaddy = attacker
		 
		if (victim == attacker) then
			deathmessage = deathmessage .. "committed **suicide**"
		else
			deathmessage = deathmessage .. "killed **"..victim:Nick().."**"
		end
			
		if IsValid(inflictor) then
			if inflictor:IsPlayer() or inflictor:IsNPC() then
				if IsValid(inflictor:GetActiveWeapon()) then
					deathmessage = deathmessage  .. " using **" .. inflictor:GetActiveWeapon():GetClass().. "**"
				end
			else
				deathmessage = deathmessage  .. " using **" .. inflictor:GetClass().. "**"
			end
		end				
	else
		messagedaddy = victim
		
		if attacker:IsVehicle() and IsValid(attacker:GetDriver()) then
			deathmessage = deathmessage .. "was killed by **" .. attacker:GetDriver():Nick() .. "**"

		else
			deathmessage = deathmessage .. "was killed by **" .. attacker:GetClass() .. "**"
		end
	end
	
	local ply = messagedaddy
	local nick = IsValid(ply) and (ply.RealName and ply:RealName() or ply:Nick())
	local sid = ply.SteamID and ply:SteamID()
	local sid64 = ply.SteamID64 and ply:SteamID64()
	
	http.Fetch("https://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		local msg = {
			{
				author = {
					name = nick,
					url = "https://steamcommunity.com/profiles/" .. sid64,
					icon_url = avatar
				},
				description = deathmessage,
				footer = {
					text = sid .. " / " .. sid64
				},
				color = DiscordRelay.HexColors.Purple
			}
		}
		--msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

		DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	end)
end)

--[[
local OldConCommand = concommand.Run
cvars.OnConVarChanged= function( convar_name, value_old, value_new )
	-- local msg = {
		-- {
			-- author = {
				-- name = "Server cvar '".. convar_name .. "' changed to: ".. value_new
				-- --url = "https://steamcommunity.com/profiles/" .. sid64,
				-- --icon_url = avatar
			-- },
			-- footer = {
				-- --text = sid .. " / " .. sid64,
				-- text = "",
			-- },
			-- color = DiscordRelay.HexColors.Green
		-- }
	-- }
	--DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	
	DiscordRelay.SendToDiscordRaw(nil, nil,   os.date("%H:%M:%S") .. " Server cvar **".. convar_name .. "** changed to **".. value_new.."**")
	return OldConCommand( Player, cmd, args )
end 
]]

hook.Add( "LagDetectorDetected", "Discord_agDetectorDetected", function()
        local msg = {
                {
                        author = {
                                name = GetHostName(),
                                url = DiscordRelay.ServerJoinURL,
                                icon_url = DiscordRelay.ServerIconURL
                        },
                        description = "Lag detected.",
                        color = DiscordRelay.HexColors.Teal
                }
        }
        --msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

        DiscordRelay.SendToDiscordRaw(nil, nil, msg)
end)
hook.Add( "LagDetectorQuiet", "Discord_LagDetectorQuiet", function()
        local msg = {
                {
                        author = {
                                name = GetHostName(),
                                url = DiscordRelay.ServerJoinURL,
                                icon_url = DiscordRelay.ServerIconURL
                        },
                        description = "Lag Subsided.",
                        color = DiscordRelay.HexColors.Teal
                }
        }
        --msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

        DiscordRelay.SendToDiscordRaw(nil, nil, msg)
end)
hook.Add( "LagDetectorMeltdown", "MyLagDetectorMeltdown", function()
        local msg = {
                {
                        author = {
                                name = GetHostName(),
                                url = DiscordRelay.ServerJoinURL,
                                icon_url = DiscordRelay.ServerIconURL
                        },
                        description = "Server meltdown.",
                        color = DiscordRelay.HexColors.Teal
                }
        }
        --msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

        DiscordRelay.SendToDiscordRaw(nil, nil, msg)
end)


hook.Add("PlayerSay", "Discord_Webhook_Chat", function(ply, text, teamchat)
	local nick = ply:Nick()
	local sid = ply:SteamID()
	local sid64 = ply:SteamID64()

	local text = text:gsub("(@everyone)", "[at]everyone")
	local text = text:gsub("(@here)", "[at]here")
	if DiscordRelay.Members then
		text = text:gsub("@([^%s.]*)", function(name)
			if name:len() < 1 then return end
			for _, user in next, DiscordRelay.Members do
				local username = user.nick or user.user.username
				if username:lower():match(name:lower()) then
					return "<@" .. user.user.id .. ">"
				end
			end
		end)
	else
		DiscordRelay.GetMembers()
	end

	http.Fetch("https://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		DiscordRelay.SendToDiscordRaw(nick, avatar, text)
	end)
end)

hook.Add("PlayerInitialSpawn", "Discord_PlayerInitilaSpawn", function (ply) 
	local nick = ply:GetName()
	local sid = ply:SteamID()
	local sid64 = ply:SteamID64()
	
	http.Fetch("https://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		local msg = {
				{
					author = {
							name = nick .. " is has spanwd in the server!",
							url = "https://steamcommunity.com/profiles/" .. sid64,
							icon_url = avatar
					},
					footer = {
							text = sid .. " / " .. sid64,
					},
					color = DiscordRelay.HexColors.Green
				}
		}
		--msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL$

		DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	end)
end )

gameevent.Listen("player_connect")
hook.Add("player_connect", "Discord_Player_Connect", function(ply)
	local nick = ply.name
	local sid = ply.networkid
	local sid64 = util.SteamIDTo64(ply.networkid)

	http.Fetch("https://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		local msg = {
			{
				author = {
					name = nick .. " is joining the server!",
					url = "https://steamcommunity.com/profiles/" .. sid64,
					icon_url = avatar
				},
				footer = {
					text = sid .. " / " .. sid64,
				},
				color = DiscordRelay.HexColors.Green
			}
		}
		--msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

		DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	end)
end)

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "Discord_Player_Disconnect", function(data)
	local ply = Player(data.userid)
	local nick = IsValid(ply) and (ply.RealName and ply:RealName() or ply:Nick()) or data.name
	local sid = ply.SteamID and ply:SteamID() or data.networkid
	local sid64 = ply.SteamID64 and ply:SteamID64() or util.SteamIDTo64(data.networkid)

	http.Fetch("https://steamcommunity.com/profiles/" .. sid64 .. "?xml=1", function(content, size)
		local avatar = content:match("<avatarFull><!%[CDATA%[(.-)%]%]></avatarFull>")
		local msg = {
			{
				author = {
					name = nick .. "  left the server.",
					url = "https://steamcommunity.com/profiles/" .. sid64,
					icon_url = avatar
				},
				description = data.reason and ("Reason: " .. data.reason) or nil,
				footer = {
					text = sid .. " / " .. sid64
				},
				color = DiscordRelay.HexColors.Red
			}
		}
		--msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

		DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	end)
end)

hook.Add("HTTPLoaded", "Discord_Announce_Active", function()
	local msg = {
		{
			author = {
				name = GetHostName(),
				url = DiscordRelay.ServerJoinURL,
				icon_url = DiscordRelay.ServerIconURL
			},
			description = "is now online, playing `" .. game.GetMap() .. "`.",
			color = DiscordRelay.HexColors.Teal
		}
	}
	--msg[1].description = msg[1].description .. "\n\n[:door: Join]("..DiscordRelay.ServerJoinURL..")"

	DiscordRelay.SendToDiscordRaw(nil, nil, msg)
	hook.Remove("HTTPLoaded", "Discord_Announce_Active") -- Just in case
end)

--[[
local function overrideulxlogstring()
	oldlogstring = oldlogstring or ulx.logString

	function ulx.logString( str, log_to_main )
		local date = os.date( "*t" )
		DiscordRelay.SendToDiscordRaw(nil, nil,  string.format( "[%02i:%02i:%02i] ", date.hour, date.min, date.sec ) .. str )
		oldlogstring( str, log_to_main )
	end
end
if ulx then overrideulxlogstring() end
hook.Add("InitPostEntity", "OverrideULXlogsting", overrideulxlogstring)
]]

local function overridefancyLogAdmin()
	oldfancyLogAdmin = oldfancyLogAdmin or ulx.fancyLogAdmin

	function ulx.fancyLogAdmin(calling_ply, format, ...)
   		oldfancyLogAdmin(calling_ply, format, ...)

		local arg_pos = 1
		local args = { ... }
		local message = ""
		local no_targets = false
		local hide_echo = false		

		if isstring(args[1]) and string.StartWith( args[1], "#P to #P" ) then return end

		if type( format ) == "boolean" then
			hide_echo = format
			format = args[ 1 ]
			arg_pos = arg_pos + 1
		end
		
		if type( format ) == "table" then
			players = format
			format = args[ 1 ]
			arg_pos = arg_pos + 1
		end
		
		format:gsub( "([^#]*)#([%.%d]*[%a])([^#]*)", function( prefix, tag, postfix )
			local specifier = tag:sub( -1, -1 )
			local arg = args[ arg_pos ]
			arg_pos = arg_pos + 1	
			
			message = message .. prefix
			
			if specifier == "A" then
				if calling_ply:IsPlayer() then 
					message = message .. calling_ply:Nick()
				else
					message = message .. "(Console)"
				end
				
				arg_pos = arg_pos - 1
			end
			
			if specifier == "i" then
				message = message .. arg
			end
			
			if specifier == "s" or specifier == "q" then
				message = message .. "\"" .. arg .. "\""
			end
			
			if specifier == "T" or specifier == "P"  then				
				if type( arg ) == "table" then
				if #arg == 0 then no_targets = true end
					for j,k in pairs(arg) do 
							if j > 1 then 
							message = message .. ", "
						end
						message = message .. k:Nick()
					end
				else
					message = message .. arg:Nick()
				end
			end 
			
			message = message .. postfix
		end)
		
		if no_targets then -- We don't want to log if there's nothing being targetted
			return
		end

		if hide_echo then return end

		local date = os.date( "*t" )
		DiscordRelay.SendToDiscordRaw(nil, nil,  string.format( "[%02i:%02i:%02i] ", date.hour, date.min, date.sec ) .. message )
	end
end
if ulx then overridefancyLogAdmin() end
hook.Add("InitPostEntity", "OverrideULXfancyLogAdmin", overridefancyLogAdmin)

-- Initialize
hook.Add("InitPostEntity", "CreateAFuckingBot", function()
	if DiscordRelay.AvoidUsingBots == false then
		print("Adding a bot to kick things off")
		game.ConsoleCommand("bot\n")

		for k, v in pairs(player.GetBots()) do
			v:Kick("Thanks for helping us out bot!")
		end
	else
		print("Attempting to force sv_hibernate_think to 1. Don't blame me for this!")
		game.ConsoleCommand("sv_hibernate_think 1\n")
	end

	hook.Remove("InitPostEntity", "CreateAFuckingBot")
end)
