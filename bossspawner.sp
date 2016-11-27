/*	
 *	============================================================================
 *	
 *	[TF2] Custom Boss Spawner
 *	Alliedmodders: https://forums.alliedmods.net/showthread.php?t=218119
 *	Current Version: 5.0.2
 *
 *	Written by Tak (Chaosxk)
 *	https://forums.alliedmods.net/member.php?u=87026
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
Version Log:
~ Next version
	- Properly use FindConvar instead of ServerCommand to execute convars ("tf_eyeball_boss_lifetime" and "tf_merasmus_lifetime").
	- Changed a bad attempt at managing convars ("tf_eyeball_boss_lifetime" and "tf_merasmus_lifetime"), plugin will now instead just set those values to 9999999 and default values when unloaded.
	- No longer caches values from convars (convars.IntValue is already cached)
	- No longer need to unhook sdkhook on client disconnect
	- Fixed a bug where round start would make the next boss timer to disappear
	- Fixed a bug where the health bar text would only work on the first map and no longer works after a map change
	- Fixed a bug where plugin should be disabled and still blocked some halloween notications/sounds
	- Fixed a bug where boss spawned from other plugin would have it's damaged changed by this plugin
	- Fixed a bug where monoculus would switch between models
	- Fixed a bug where merasmus would switch between skins/colors
	- Changed warhammer boss from chaos_bosspack config "WeaponModel" to Invisible 
	- Updated some syntax and code clean up
	- Optimization of code
	- General code cleanup

v.5.0.2
	- Fixed skeleton dispatching wrong blood color and spawning them on wrong team
	- Added new glow colors to menu, orange, navy, pink, aquamarine, peachpuff, white
v.5.0.1
	- Fixed HUD text and bar not disapearing when bosses die
v.5.0
	- Fixed custom models causing bosses to stop moving and attacking (Uses bonemerge)
	- Glow colors can be changed through spawn menu or through bossspawner_boss.cfg (spawn menu will override the config) or through command
			Spawn menu - colored glows (Red Green Blue Yellow Purple Cyan Orange Pink Black)
			Config - colored glows from RGB - Alpha values("0-255 0-255 0-255 0-255")(E.G "255 0 0 255" will make Red, "0 255 0 255" will make Green, "0 0 255 255" will make Blue)
			Command - colored glows from RGB - !<bossname> <health> <size> <R,G,B,A> where RGBA values vary from 0-255, Example: !horseman 1000 1 255,0,255,255 (horseman will spawn with 1000 hp with purple glow)
	- Changed sm_boss_vote as a percentage between 0-100 instead of amount of players
	- May have fixed a call stack trace error on OnEntityDestroyed()
	- Updated bossspawner_boss.cfg - Added colors and modified King and Warhammer "PosFix" values from 300 to 5 so it doesn't spawn way over than it should
	- Removed bossspawner_vanilla.cfg - No longer supporting
	- Updated the README.txt file instructions to be clearer
	
New default bosses: (Bosses that do not require any model/material downloads)
	- Demobot
	- Heavybot
	- Pyrobot
	- Scoutbot
	- Soldierbot
	- Spybot
	- Sniperbot
	- Medicbot
	- Engineerbot
	- Tank
	- Ghost
	- Sentrybuster
	- Botkiller

Known bugs: 
	- Horseman axe will NOT glow
	- Merasmus will tend to randomly change color from green to normal
	- Monoculus can no longer have model replacement due to some complications
	- Botkiller and Ghost can not be resized
	- When tf_skeleton with a hat attacks you while standing still, his hat model may freeze until he starts moving
	- eyeball_boss can die from collision from a payload cart, most of time in air so it doesn't matter too much
	- Hat size and offset does not change if player manually spawns a boss with a different size from the config (e.g !horseman 1000 5 1 : Horseman size is 5 but default size in boss config is 1, if this boss has a hat the hat won't resize)
 *	============================================================================
 */
#pragma semicolon 1
#include <morecolors>
#include <sdktools>
#pragma newdecls required
#include <sourcemod>
#include <sdkhooks>

#define PLUGIN_VERSION "5.0.2"
#define INTRO_SND	"ui/halloween_boss_summoned_fx.wav"
#define DEATH_SND	"ui/halloween_boss_defeated_fx.wav"
#define HORSEMAN	"headless_hatman"
#define MONOCULUS	"eyeball_boss"
#define MERASMUS	"merasmus"
#define SKELETON	"tf_zombie"
#define SNULL 		""

#define EF_NODRAW				(1 << 5)
#define EF_BONEMERGE            (1 << 0)
#define EF_NOSHADOW             (1 << 4)
#define EF_BONEMERGE_FASTCULL   (1 << 7)
#define EF_PARENT_ANIMATES      (1 << 9)

ConVar g_cEyeball_Lifetime, g_cMerasmus_Lifetime;
Handle cTimer = null;
ArrayList gArray = null;
ArrayList gData = null;

//Variables for ConVars conversion
bool gEnabled;

//Other variables
int gIndex, gIndexCmd;
float gPos[3], kPos[3];
int g_AutoBoss, gTrack = -1, gHPbar = -1;

int gVotes[MAXPLAYERS+1];

//Index saving
int argIndex, saveIndex;

ConVar g_cMode, g_cInterval, g_cMinplayers, g_cHudx, g_cHudy, g_cHealthbar, g_cVote;
int g_iEyeball_Default, g_iMerasmus_Default;
int g_iInterval, g_iTotalVotes;

public Plugin myinfo = 
{
	name = "[TF2] Custom Boss Spawner",
	author = "Tak (chaosxk)",
	description = "A customizable boss spawner",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public void OnPluginStart()
{
	CreateConVar("sm_boss_version", PLUGIN_VERSION, "Custom Boss Spawner Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	g_cMode = 		CreateConVar("sm_boss_mode", 		"1", 	"Spawn mode for auto-spawning [0:Random | 1:Ordered | 2:Vote]");
	g_cInterval = 	CreateConVar("sm_boss_interval", 	"300", 	"How many seconds until the next boss spawns?");
	g_cMinplayers = CreateConVar("sm_boss_minplayers", 	"12", 	"How many players are needed before enabling auto-spawning?");
	g_cHudx = 		CreateConVar("sm_boss_hud_x", 		"0.05", "X-Coordinate of the HUD display.");
	g_cHudy = 		CreateConVar("sm_boss_hud_y", 		"0.05", "Y-Coordinate of the HUD display");
	g_cHealthbar = 	CreateConVar("sm_healthbar_type", 	"3", 	"What kind of healthbar to display? [0:None | 1:HUDBar | 2:HUDText | 3:Both]");
	g_cVote = 		CreateConVar("sm_boss_vote", 		"50", 	"How many people are needed to type !voteboss before a vote starts to spawn a boss? [0-100] as percentage");
	
	RegAdminCmd("sm_getcoords", GetCoords, 	ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_forceboss", ForceBoss, 	ADMFLAG_GENERIC, "Forces a auto-spawning boss to spawn early.");
	RegAdminCmd("sm_fb", 		ForceBoss, 	ADMFLAG_GENERIC, "Forces a auto-spawning boss to spawn early.");
	RegAdminCmd("sm_spawnboss", SpawnMenu,	ADMFLAG_GENERIC, "Opens a menu to spawn a boss.");
	RegAdminCmd("sm_sb", 		SpawnMenu,	ADMFLAG_GENERIC, "Opens a menu to spawn a boss.");
	RegAdminCmd("sm_slayboss", 	SlayBoss,	ADMFLAG_GENERIC, "Slay all active bosses on map.");
	RegAdminCmd("sm_forcevote", ForceVote,	ADMFLAG_GENERIC, "Start a vote, this is the same as !forceboss if sm_boss_mode was set to 2");
	
	RegConsoleCmd("sm_voteboss", VoteBoss, "Start a vote, needs minimum amount of people to run this command to start a vote.  Follows sm_boss_vote");
	
	HookEvent("teamplay_round_start", 			RoundStart,		EventHookMode_Pre);
	HookEvent("pumpkin_lord_summoned", 			Boss_Summoned, 	EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", 			Boss_Summoned, 	EventHookMode_Pre);
	HookEvent("merasmus_summoned", 				Boss_Summoned, 	EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", 			Boss_Killed, 	EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", 			Boss_Killed, 	EventHookMode_Pre);
	HookEvent("merasmus_killed", 				Boss_Killed, 	EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", 		Merasmus_Leave, EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", 	Monoculus_Leave,EventHookMode_Pre);
	
	HookUserMessage(GetUserMessageId("SayText2"), SayText2, true);
	
	gArray = new ArrayList();
	gData = new ArrayList();
	
	CreateTimer(0.5, HealthTimer, _, TIMER_REPEAT);

	g_cEyeball_Lifetime = FindConVar("tf_eyeball_boss_lifetime");
	g_cMerasmus_Lifetime = FindConVar("tf_merasmus_lifetime");
	g_iEyeball_Default = g_cEyeball_Lifetime.IntValue;
	g_iMerasmus_Default = g_cMerasmus_Lifetime.IntValue;
	
	g_cMinplayers.AddChangeHook(OnConvarChanged);
	g_cInterval.AddChangeHook(OnConvarChanged);
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	
	AutoExecConfig(false, "bossspawner");  
}

public void OnPluginEnd()
{
	//When plugin is unloaded, remove any bosses on map and set the monoculus/merasmus convars back to their default values
	RemoveExistingBoss();
	SetEyeballLifetime(g_iEyeball_Default);
	SetMerasmusLifetime(g_iMerasmus_Default);
}

public void OnConfigsExecuted() 
{	
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupBossConfigs("bossspawner_boss.cfg");
	SetupDownloads("bossspawner_downloads.cfg");
	
	if (!gEnabled)
		return;
		
	FindHealthBar();
	PrecacheSound("items/cart_explode.wav");
	
	for (int i = 1; i <= MaxClients; i++)
		if(IsClientInGame(i))
			SDKHook(i, SDKHook_OnTakeDamage, OnClientDamaged);
}

public void OnMapEnd()
{
	delete cTimer;
	RemoveExistingBoss();
}

public void OnClientPostAdminCheck(int client)
{
	if (GetClientCount(true) == g_cMinplayers.IntValue)
		if(g_AutoBoss == 0)
			ResetTimer();
			
	if (!gEnabled)
		return;
		
	SDKHook(client, SDKHook_OnTakeDamage, OnClientDamaged);
}

public void OnClientDisconnect_Post(int client)
{
	if (GetClientCount(true) < g_cMinplayers.IntValue)
		delete cTimer;
	gVotes[client] = 0;
	g_iTotalVotes--;
}

public void OnConvarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	if (StrEqual(oldValue, newValue, true))
		return;
		
	if (convar == g_cMinplayers)
	{
		if (!g_AutoBoss)
			ResetTimer();
		else
			delete cTimer;
	}
	else if (convar == g_cInterval)
		g_iInterval = StringToInt(newValue);
}

public Action SayText2(UserMsg msg_id, Handle bf, int[] players, int playersNum, bool reliable, bool init)
{
	if (!gEnabled)
		return Plugin_Continue;
		
	if (!reliable) 
		return Plugin_Continue;
	
	char buffer[128];
	BfReadByte(bf);
	BfReadByte(bf);
	
	BfReadString(bf, buffer, sizeof(buffer));
	
	if (StrEqual(buffer, "#TF_Halloween_Boss_Killers") || StrEqual(buffer, "#TF_Halloween_Eyeball_Boss_Killers") || StrEqual(buffer, "#TF_Halloween_Merasmus_Killers"))
		return Plugin_Handled;
		
	return Plugin_Continue;
}

/* -----------------------------------EVENT HANDLES-----------------------------------*/
public Action RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_AutoBoss = 0;
	
	if (!gEnabled)
		return Plugin_Continue;
	
	delete cTimer;
	
	if (GetClientCount(true) >= g_cMinplayers.IntValue)
	{
		ResetTimer();
	}
	return Plugin_Continue;
}

public Action Boss_Summoned(Event event, const char[] name, bool dontBroadcast)
{
	if (!gEnabled)
		return Plugin_Continue;
	return Plugin_Handled;
}

public Action Boss_Killed(Event event, const char[] name, bool dontBroadcast)
{
	if (!gEnabled)
		return Plugin_Continue;
	return Plugin_Handled;
}

public Action Merasmus_Leave(Event event, const char[] name, bool dontBroadcast)
{
	if (!gEnabled)
		return Plugin_Continue;
	return Plugin_Handled;
}

public Action Monoculus_Leave(Event event, const char[] name, bool dontBroadcast)
{
	if (!gEnabled)
		return Plugin_Continue;
	return Plugin_Handled;
}
/* -----------------------------------EVENT HANDLES-----------------------------------*/

/* ---------------------------------COMMAND FUNCTION----------------------------------*/

public Action VoteBoss(int client, int args)
{
	if (!gEnabled)
	{
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	
	if (!IsClientInGame(client))
		return Plugin_Handled;
		
	if (!gVotes[client])
	{
		gVotes[client] = 1;
		g_iTotalVotes++;
		
		int percentage = (g_iTotalVotes / GetClientCount(true) * 100);
		
		if (percentage >= g_cVote.IntValue)
		{
			for(int i = 0; i < MaxClients; i++)
				gVotes[i] = 0;
			delete cTimer;
			CreateVote();
		}
		else
			CPrintToChatAll("{frozen}[Boss] {orange}%N has casted a vote! %d%% out of %d%% is needed to start a vote!", client, percentage, g_cVote.IntValue);
	}
	else
		CReplyToCommand(client, "{frozen}[Boss] {orange}You have already casted a vote!");
	return Plugin_Handled;
}

public Action ForceBoss(int client, int args)
{
	if (!gEnabled)
	{
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	
	if (args == 1)
	{
		saveIndex = gIndex;
		char arg1[32], sName[64];
		GetCmdArg(1, arg1, sizeof(arg1));
		int i;
		for (i = 0; i < gArray.Length; i++)
		{
			StringMap HashMap = gArray.Get(i);
			HashMap.GetString("Name", sName, sizeof(sName));
			if (StrEqual(sName, arg1, false))
			{
				gIndex = i; break;
			}
		}
		
		if (i == gArray.Length)
		{
			CReplyToCommand(client, "{frozen}[Boss] {red}Error: {orange}Boss does not exist.");
			return Plugin_Handled;
		}
		argIndex = 1;
		delete cTimer;
		char sGlow[32];
		CreateBoss(gIndex, gPos, -1, -1, -1.0, sGlow, false, true);
	}
	else if (args == 0)
	{
		argIndex = 0;
		delete cTimer;
		SpawnBoss();
	}
	else
		CReplyToCommand(client, "{frozen}[Boss] {red}Format: {orange}!forceboss <bossname>");
	return Plugin_Handled;
}

public Action GetCoords(int client, int args)
{
	if (!gEnabled)
	{
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	
	float l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	CReplyToCommand(client, "{frozen}[Boss] {orange}Coordinates: %0.0f,%0.0f,%0.0f\n{frozen}[Boss] {orange}Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action SlayBoss(int client, int args)
{
	if (!gEnabled)
	{
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	
	RemoveExistingBoss();
	CReplyToCommand(client, "%t", "Boss_Slain");
	return Plugin_Handled;
}

public Action ForceVote(int client, int args)
{
	if (!gEnabled)
	{
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	delete cTimer;
	CreateVote();
	CReplyToCommand(client, "%t", "Vote_Forced");
	return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	char arg[4][64];
	int args = ExplodeString(sArgs, " ", arg, sizeof(arg), sizeof(arg[]));
	
	if (arg[0][0] == '!' || arg[0][0] == '/')
		strcopy(arg[0], 64, arg[0][1]);
	else 
		return Plugin_Continue;
		
	int i; StringMap HashMap; char sName[64];
	
	for (i = 0; i < gArray.Length; i++)
	{
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		
		if (StrEqual(sName, arg[0], false))
			break;
	}
	if (i == gArray.Length)
		return Plugin_Continue;
		
	if (!gEnabled)
	{
		CPrintToChat(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	
	if (!CheckCommandAccess(client, "sm_boss_override", ADMFLAG_GENERIC, false))
	{
		CPrintToChat(client, "{frozen}[Boss] {orange}You do not have access to this command.");
		return Plugin_Handled;
	}
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		CPrintToChat(client, "{frozen}[Boss] {orange}You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	
	if (!SetTeleportEndPoint(client))
	{
		CPrintToChat(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	
	kPos[2] -= 10.0;
	int iBaseHP = -1, iScaleHP = -1;
	char sGlow[32];
	float iSize = -1.0;
	
	if (args < 1 || args > 4)
	{
		CPrintToChat(client, "{Frozen}[Boss] {orange}Incorrect parameters: !<bossname> <health> <optional:size> <optional:RGBA values for color>");
		CPrintToChat(client, "{Frozen}[Boss] {orange}Example usage: !horseman 1000 2 255,255,255,255");
		return Plugin_Handled;
	}
	else
	{
		if(args > 1)
		{
			iBaseHP = StringToInt(arg[1]);
			iScaleHP = 0;
		}
		
		if(args > 2)
			iSize = StringToFloat(arg[2]);
			
		if(args > 3)
		{
			Format(sGlow, sizeof(sGlow), "%s", arg[3]);
			ReplaceString(sGlow, sizeof(sGlow), ",", " ", false);
		}
	}
	gIndexCmd = i;
	
	CreateBoss(gIndexCmd, kPos, iBaseHP, iScaleHP, iSize, sGlow, true, false);
	return Plugin_Handled;
}

public Action SpawnBossCommand(int client, const char[] command, int args)
{
	char arg1[64], arg2[32], arg3[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	int i;
	StringMap HashMap = null;
	char sName[64];
	int nIndex = FindCharInString(command, '_', _) + 1;
	char command2[64];
	strcopy(command2, sizeof(command2), command[nIndex]);
	
	for (i = 0; i < gArray.Length; i++)
	{
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		
		if(StrEqual(sName, command2, false))
			break;
	}
	if (i == gArray.Length)
		return Plugin_Continue;
		
	if (!gEnabled)
	{
		CPrintToChat(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	
	if (!CheckCommandAccess(client, "sm_boss_override", ADMFLAG_GENERIC, false))
	{
		CPrintToChat(client, "{frozen}[Boss] {orange}You do not have access to this command.");
		return Plugin_Handled;
	}
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		CPrintToChat(client, "{frozen}[Boss] {orange}You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	
	if (!SetTeleportEndPoint(client))
	{
		CPrintToChat(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	int iBaseHP = -1, iScaleHP = -1;
	char sGlow[32];
	float iSize = -1.0;
	
	if (args < 0 || args > 3)
	{
		CPrintToChat(client, "{Frozen}[Boss] {orange}Incorrect parameters: !<bossname> <health> <optional:size> <optional:RGBA values for color>");
		CPrintToChat(client, "{Frozen}[Boss] {orange}Example usage: !horseman 1000 2 255,255,255,255");
		return Plugin_Handled;
	}
	else
	{
		if (args > 0)
		{
			GetCmdArg(1, arg1, sizeof(arg1));
			iBaseHP = StringToInt(arg1);
			iScaleHP = 0;
		}
		
		if (args > 1)
		{
			GetCmdArg(2, arg2, sizeof(arg2));
			iSize = StringToFloat(arg2);
		}
		
		if (args > 2)
		{
			GetCmdArg(3, arg3, sizeof(arg3));
			Format(sGlow, sizeof(sGlow), "%s", arg3);
			ReplaceString(sGlow, sizeof(sGlow), ",", " ", false);
		}
	}
	gIndexCmd = i;
	CreateBoss(gIndexCmd, kPos, iBaseHP, iScaleHP, iSize, sGlow, true, false);
	return Plugin_Handled;
}

public Action SpawnMenu(int client, int args)
{
	if (!gEnabled)
	{
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if (!IsClientInGame(client))
	{
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	ShowMenu(client);
	return Plugin_Handled;
}

public void ShowMenu(int client)
{
	StringMap HashMap = null;
	char sName[64], sInfo[8];
	Menu menu = new Menu(DisplayHealth);
	SetMenuTitle(menu, "Boss Menu");
	for (int i = 0; i < gArray.Length; i++)
	{
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		IntToString(i, sInfo, sizeof(sInfo));
		menu.AddItem(sInfo, sName);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int DisplayHealth(Menu MenuHandle, MenuAction action, int client, int num)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(DisplaySizes);
		menu.SetTitle("Boss Health");
		char param[32];
		char health[][] = {"1000", "5000", "10000", "15000", "20000", "30000", "50000"};
		for (int i = 0; i < sizeof(health); i++)
		{
			Format(param, sizeof(param), "%s %s", info, health[i]);
			menu.AddItem(param, health[i]);
		}
		SetMenuExitButton(menu, true);
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
		delete MenuHandle;
}

public int DisplaySizes(Menu MenuHandle, MenuAction action, int client, int num)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(DisplayGlow);
		menu.SetTitle("Boss Size");
		char param[32];
		char size[][] = {"0.5", "1.0", "1.5", "2.0", "3.0", "4.0", "5.0"};
		for (int i = 0; i < sizeof(size); i++)
		{
			Format(param, sizeof(param), "%s %s", info, size[i]);
			menu.AddItem(param, size[i]);
		}
		SetMenuExitButton(menu, true);
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
		delete MenuHandle;
}

public int DisplayGlow(Menu MenuHandle, MenuAction action, int client, int num)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(EndMenu);
		menu.SetTitle("Boss Glow");
		char param[32];
		
		Format(param, sizeof(param), "%s 0,255,0,255", info);
		menu.AddItem(param, "Green");
		Format(param, sizeof(param), "%s 255,255,0,255", info);
		menu.AddItem(param, "Yellow");
		Format(param, sizeof(param), "%s 255,165,0,255", info);
		menu.AddItem(param, "Orange");
		Format(param, sizeof(param), "%s 255,0,0,255", info);
		menu.AddItem(param, "Red");
		Format(param, sizeof(param), "%s 0,0,128,255", info);
		menu.AddItem(param, "Navy");
		Format(param, sizeof(param), "%s 0,0,255,255", info);
		menu.AddItem(param, "Blue");
		Format(param, sizeof(param), "%s 255,0,255,255", info);
		menu.AddItem(param, "Purple");
		Format(param, sizeof(param), "%s 0,255,255,255", info);
		menu.AddItem(param, "Cyan");
		Format(param, sizeof(param), "%s 255,192,203,255", info);
		menu.AddItem(param, "Pink");
		Format(param, sizeof(param), "%s 127,255,212,255", info);
		menu.AddItem(param, "Aquamarine");
		Format(param, sizeof(param), "%s 255,218,185,255", info);
		menu.AddItem(param, "Peachpuff");
		Format(param, sizeof(param), "%s 255,255,255,255", info);
		menu.AddItem(param, "White");
		Format(param, sizeof(param), "%s 0,0,0,0", info);
		menu.AddItem(param, "None");
			
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
		delete MenuHandle;
}

public int EndMenu(Menu MenuHandle, MenuAction action, int client, int num)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		char sAttribute[4][16];
		ExplodeString(info, " ", sAttribute, sizeof(sAttribute), sizeof(sAttribute[]));
		int iIndex, iBaseHP;
		float iSize;
		iIndex = StringToInt(sAttribute[0]);
		iBaseHP = StringToInt(sAttribute[1]);
		iSize = StringToFloat(sAttribute[2]);
		ReplaceString(sAttribute[3], sizeof(sAttribute[]), ",", " ", false);
		
		if (!SetTeleportEndPoint(client)) {
			CReplyToCommand(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
			return;
		}
		
		kPos[2] -= 10.0;
		CreateBoss(iIndex, kPos, iBaseHP, 0, iSize, sAttribute[3], true, false);
	}
	else if (action == MenuAction_End)
		delete MenuHandle;
}

bool SetTeleportEndPoint(int client)
{
	float vAngles[3], vOrigin[3], vBuffer[3], vStart[3], Distance;

	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceentFilterPlayer);

	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		kPos[0] = vStart[0] + (vBuffer[0]*Distance);
		kPos[1] = vStart[1] + (vBuffer[1]*Distance);
		kPos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else
	{
		delete trace;
		return false;
	}

	delete trace;
	return true;
}

public bool TraceentFilterPlayer(int ent, int contentsMask)
{
	return ent > GetMaxClients() || !ent;
}

public void CreateVote()
{
	if (IsVoteInProgress())
		return;
		
	CPrintToChatAll("{frozen}[Boss] {orange}A vote has been started to spawn the next boss!");
	//create a random list to push random bosses
	ArrayList randomList = new ArrayList();
	//then clone the original array so we don't mess with the original
	ArrayList copyList = gArray.Clone();
	
	//we loop through the copy list and get a random hash and push it to the random list then erase the index from copylist
	while (copyList.Length != 0)
	{
		int rand = GetRandomInt(0, copyList.Length-1);
		randomList.Push(copyList.Get(rand));
		copyList.Erase(rand);
	}
	char iData[64], sName[64];
	Menu menu = new Menu(Handle_VoteMenu);
	for (int i = 0; i < randomList.Length; i++)
	{
		StringMap HashMap = randomList.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		int index = gArray.FindValue(HashMap);
		Format(iData, sizeof(iData), "%d", index);
		menu.SetTitle("Vote for the next boss!");
		menu.AddItem(iData, sName);
	}
	menu.ExitButton = false;
	menu.DisplayVoteToAll(20);
	delete randomList;
	delete copyList;
}

public int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_VoteEnd)
	{
		char iData[64];
		menu.GetItem(param1, iData, sizeof(iData));
		int index = StringToInt(iData);
		char sGlow[32];
		CreateBoss(index, gPos, -1, -1, -1.0, sGlow, false, true);
	}
}

/* ---------------------------------COMMAND FUNCTION----------------------------------*/

/* --------------------------------BOSS SPAWNING CORE---------------------------------*/

public void SpawnBoss()
{
	char sGlow[32];
	switch (g_cMode.IntValue)
	{
		case 0:
		{
			gIndex = GetRandomInt(0, gArray.Length-1);
			CreateBoss(gIndex, gPos, -1, -1, -1.0, sGlow, false, true);
		}
		case 1: CreateBoss(gIndex, gPos, -1, -1, -1.0, sGlow, false, true);
		case 2: CreateVote();
	}
}

public void CreateBoss(int index, float kpos[3], int iBaseHP, int iScaleHP, float iSize, const char[] sGlowValue, bool isCMD, bool timed)
{
	float temp[3];
	for (int i = 0; i < 3; i++)
		temp[i] = kpos[i];
	
	char sName[64], sModel[256], sType[32], sBase[16], sScale[16], sSize[16], sGlow[32], sPosFix[32];
	char sLifetime[32], sPosition[32], sHorde[8], sColor[16], sHModel[256], sISound[256], sHatPosFix[32], sHatSize[16];

	StringMap HashMap = gArray.Get(index);
	HashMap.GetString("Name", sName, sizeof(sName));
	HashMap.GetString("Model", sModel, sizeof(sModel));
	HashMap.GetString("Type", sType, sizeof(sType));
	HashMap.GetString("Base", sBase, sizeof(sBase));
	HashMap.GetString("Scale", sScale, sizeof(sScale));
	HashMap.GetString("Size", sSize, sizeof(sSize));
	HashMap.GetString("Glow", sGlow, sizeof(sGlow));
	HashMap.GetString("PosFix", sPosFix, sizeof(sPosFix));
	HashMap.GetString("Lifetime", sLifetime, sizeof(sLifetime));
	HashMap.GetString("Position", sPosition, sizeof(sPosition));
	HashMap.GetString("Horde", sHorde, sizeof(sHorde));
	HashMap.GetString("Color", sColor, sizeof(sColor));
	HashMap.GetString("HatModel", sHModel, sizeof(sHModel));
	HashMap.GetString("IntroSound", sISound, sizeof(sISound));
	HashMap.GetString("HatPosFix", sHatPosFix, sizeof(sHatPosFix));
	HashMap.GetString("HatSize", sHatSize, sizeof(sHatSize));
	
	if (iBaseHP == -1)
		iBaseHP = StringToInt(sBase);
		
	if (iScaleHP == -1)
		iScaleHP = StringToInt(sScale);
		
	if (iSize == -1.0)
		iSize = StringToFloat(sSize);
		
	if (strlen(sPosition) != 0 && !isCMD)
	{
		char sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		
		for(int i = 0; i < 3; i++)
			temp[i] = StringToFloat(sPos[i]);
	}
	
	temp[2] += StringToFloat(sPosFix);
	int iMax = StringToInt(sHorde) <= 1 ? 1 : StringToInt(sHorde);
	int playerCounter = GetClientCount(true);
	int sHealth = (iBaseHP + iScaleHP*playerCounter)*(iMax != 1 ? 1 : 10);
	DataPack dMax = new DataPack();
	dMax.WriteCell(iMax);
	
	for (int i = 0; i < iMax; i++)
	{
		int ent = CreateEntityByName(sType);
		ArrayList dReference = new ArrayList();
		dReference.Push(dMax);
		dReference.Push(EntIndexToEntRef(ent));
		dReference.Push(index);
		dReference.Push(timed);
		gData.Push(dReference);
		
		TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(ent);
		
		ResizeHitbox(ent, iSize);
		SetSize(iSize, ent);
		
		SetEntProp		(ent, Prop_Data, "m_iHealth", 		sHealth);
		SetEntProp		(ent, Prop_Data, "m_iMaxHealth", 	sHealth); 
		
		SetEntProp		(ent, Prop_Data, "m_iTeamNum", 		(strcmp(sType, MONOCULUS) == 0 || strcmp(sType, SKELETON) == 0) ? 5 : 0);
		//speed don't work! -.-
		//SetEntPropFloat	(ent, Prop_Data, "m_flSpeed", 	0.0);
		
		int attach = ent;
		char targetname[128];
		Format(targetname, sizeof(targetname), "%s%d", sName, GetRandomInt(2000, 10000));
		//Creates boss model to bonemerge
		if (strlen(sModel))
		{
			if (!StrEqual(sType, MONOCULUS))
			{
				int model = CreateEntityByName("prop_dynamic_override");
				attach = model;
				
				DispatchKeyValue(model, "targetname", targetname);
				DispatchKeyValue(model, "model", sModel);
				DispatchKeyValue(model, "solid", "0");
				SetEntPropEnt(model, Prop_Send, "m_hOwnerEntity", ent);
				SetEntProp(model, Prop_Send, "m_fEffects", EF_BONEMERGE|EF_NOSHADOW|EF_PARENT_ANIMATES);
				
				TeleportEntity(model, kpos, NULL_VECTOR, NULL_VECTOR);
				DispatchSpawn(model);
				
				SetVariantString("!activator");
				AcceptEntityInput(model, "SetParent", ent, model, 0);
				
				SetVariantString("head"); 
				AcceptEntityInput(model, "SetParentAttachment", ent, model, 0);
				
				SetEntProp(ent, Prop_Send, "m_fEffects", EF_NODRAW);
			}
			else
			{
				DispatchKeyValue(ent, "targetname", targetname);
			}
		}
		else
		{
			DispatchKeyValue(ent, "targetname", targetname);
		}
		
		if (strlen(sColor) != 0)
		{
			if(StrEqual(sColor, "Red", false)) SetEntProp(attach, Prop_Send, "m_nSkin", 0);
			else if(StrEqual(sColor, "Blue", false)) SetEntProp(attach, Prop_Send, "m_nSkin", 1);
			else if(StrEqual(sColor, "Green", false)) SetEntProp(attach, Prop_Send, "m_nSkin", 2);
			else if(StrEqual(sColor, "Yellow", false)) SetEntProp(attach, Prop_Send, "m_nSkin", 3);
			else if(StrEqual(sColor, "Random", false)) SetEntProp(attach, Prop_Send, "m_nSkin", GetRandomInt(0, 3));
		}
		
		if (!sGlowValue[0])
			SetGlow(ent, targetname, kpos, sGlow);
		else
			SetGlow(ent, targetname, kpos, sGlowValue);
		
		if (timed) 
			g_AutoBoss++;
			
		if (i == 0)
		{
			DataPack hPack;
			CreateDataTimer(1.0, RemoveTimerPrint, hPack, TIMER_REPEAT);
			hPack.WriteCell(EntIndexToEntRef(ent));
			hPack.WriteCell(StringToFloat(sLifetime));
			hPack.WriteCell(index);
		}
		
		DataPack jPack;
		CreateDataTimer(1.0, RemoveTimer, jPack, TIMER_REPEAT);
		jPack.WriteCell(EntIndexToEntRef(ent));
		jPack.WriteCell(StringToFloat(sLifetime));
		
		if (strlen(sHModel) != 0)
		{
			int hat = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(hat, "model", sHModel);
			DispatchKeyValue(hat, "spawnflags", "256");
			DispatchKeyValue(hat, "solid", "0");
			SetEntPropEnt(hat, Prop_Send, "m_hOwnerEntity", attach);
			//Hacky tacky way..
			//SetEntPropFloat(hat, Prop_Send, "m_flModelScale", iSize > 5 ? (iSize > 10 ? (iSize/5+0.80) : (iSize/4+0.75)) : (iSize/3+0.66));
			SetEntPropFloat(hat, Prop_Send, "m_flModelScale", StringToFloat(sHatSize));
			//SetEntPropFloat(hat, Prop_Send, "m_flModelScale", iSize*StringToFloat(sHatSize));
			DispatchSpawn(hat);	
			
			SetVariantString("!activator");
			AcceptEntityInput(hat, "SetParent", attach, hat, 0);
			
			//maintain the offset of hat to the center of head
			if (!StrEqual(sType, MONOCULUS))
			{
				SetVariantString("head");
				AcceptEntityInput(hat, "SetParentAttachment", attach, hat, 0);
				SetVariantString("head");
				AcceptEntityInput(hat, "SetParentAttachmentMaintainOffset", attach, hat, 0);
			}
			
			float hatpos[3];
			hatpos[2] += StringToFloat(sHatPosFix);//*iSize; //-9.5*iSize
			//hatpos[0] += -5.0;
			TeleportEntity(hat, hatpos, NULL_VECTOR, NULL_VECTOR);
		}
	}
	
	if (!StrEqual(sISound, "none", false))
		EmitSoundToAll(sISound, _, _, _, _, 1.0);
		
	ReplaceString(sName, sizeof(sName), "_", " ");
	CPrintToChatAll("%t", "Boss_Spawn", sName);
	
	if (argIndex == 1)
		gIndex = saveIndex;
	
	if (timed)
	{
		gIndex++;
		if (gIndex > gArray.Length-1) 
			gIndex = 0;
	}
}

public Action RemoveTimer(Handle hTimer, DataPack jPack)
{
	jPack.Reset();
	int ent = EntRefToEntIndex(jPack.ReadCell());
	
	if (!IsValidEntity(ent))
		return Plugin_Stop;
		
	float tcounter = jPack.ReadCell();
	if (tcounter <= 0.0)
	{
		AcceptEntityInput(ent, "Kill");
		return Plugin_Stop;
	}
	else
	{
		tcounter -= 1.0;
		jPack.Reset();
		jPack.ReadCell();
		jPack.WriteCell(tcounter);
		return Plugin_Continue;
	}
}

public Action RemoveTimerPrint(Handle hTimer, DataPack hPack)
{
	hPack.Reset();
	int ent = EntRefToEntIndex(hPack.ReadCell());
	
	if (!IsValidEntity(ent))
		return Plugin_Stop;
		
	float tcounter = hPack.ReadCell();
	if (tcounter <= 0.0)
	{
		int index = hPack.ReadCell();
		char sName[64];
		StringMap HashMap = gArray.Get(index);
		HashMap.GetString("Name", sName, sizeof(sName));
		CPrintToChatAll("%t", "Boss_Left", sName);
		return Plugin_Stop;
	}
	else
	{
		tcounter -= 1.0;
		hPack.Reset();
		hPack.ReadCell();
		hPack.WriteCell(tcounter);
		return Plugin_Continue;
	}
}

//Instead of hooking to sdkhook_takedamage, we use a 0.5 timer because of hud overloading when taking damage
public Action HealthTimer(Handle hTimer, any ref)
{
	if (g_cHealthbar.IntValue == 0 || g_cHealthbar.IntValue == 1)
		return Plugin_Continue;
		
	if (gTrack != -1 && IsValidEntity(gTrack))
	{
		int HP = GetEntProp(gTrack, Prop_Data, "m_iHealth");
		int maxHP = GetEntProp(gTrack, Prop_Data, "m_iMaxHealth");
		int currentHP = RoundFloat(HP - maxHP * 0.9);
		
		if (currentHP > maxHP*0.1*0.65) 
			SetHudTextParams(0.46, 0.12, 0.5, 0, 255, 0, 255);
		else if (maxHP*0.1*0.25 < currentHP < maxHP*0.1*0.65) 
			SetHudTextParams(0.46, 0.12, 0.5, 255, 255, 0, 255);
		else 
			SetHudTextParams(0.46, 0.12, 0.5, 255, 0, 0, 255);
			
		if (currentHP <= 0) 
		{
			SetHudTextParams(0.46, 0.12, 0.5, 0, 0, 0, 0);
			currentHP = 0;
		}
		
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i)) {
				ShowHudText(i, -1, "HP: %d", currentHP);
		}
	}
	return Plugin_Continue;
}

void RemoveExistingBoss()
{
	int ent;
	while ((ent = FindEntityByClassname(ent, "headless_hatman")) != -1)
		AcceptEntityInput(ent, "Kill");
			
	while ((ent = FindEntityByClassname(ent, "eyeball_boss")) != -1)
		AcceptEntityInput(ent, "Kill");
			
	while ((ent = FindEntityByClassname(ent, "merasmus")) != -1)
		AcceptEntityInput(ent, "Kill");
			
	while ((ent = FindEntityByClassname(ent, "tf_zombie")) != -1)
			AcceptEntityInput(ent, "Kill");
			
	SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", 0);
}

void SetSize(float value, int ent)
{
	SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
}

void SetGlow(int ent, const char[] targetname, float kpos[3], const char[] sGlowValue)
{
	int glow = CreateEntityByName("tf_glow");
			
	DispatchKeyValue(glow, "glowcolor", sGlowValue);
	DispatchKeyValue(glow, "target", targetname);
	SetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity", ent);
	TeleportEntity(glow, kpos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(glow);
	
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", ent, glow, 0);
	
	AcceptEntityInput(glow, "Enable");
}

void ResizeHitbox(int entity, float fScale)
{
	float vecBossMin[3], vecBossMax[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vecBossMin);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecBossMax);
	
	float vecScaledBossMin[3], vecScaledBossMax[3];
	
	vecScaledBossMin = vecBossMin;
	vecScaledBossMax = vecBossMax;
	
	ScaleVector(vecScaledBossMin, fScale);
	ScaleVector(vecScaledBossMax, fScale);
	
	SetEntPropVector(entity, Prop_Send, "m_vecMins", vecScaledBossMin);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecScaledBossMax);
}

/* --------------------------------BOSS SPAWNING CORE---------------------------------*/

/* ---------------------------------TIMER & HUD CORE----------------------------------*/

public void CreateCountdownTimer()
{
	if (!gEnabled) 
		return;
	g_iInterval = g_cInterval.IntValue;
	cTimer = CreateTimer(1.0, Timer_HUDCounter, _, TIMER_REPEAT);
}

public Action Timer_HUDCounter(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SetHudTextParams(g_cHudx.FloatValue, g_cHudy.FloatValue, 1.0, 255, 255, 255, 255);
			ShowHudText(i, -1, "Boss: %d seconds", g_iInterval);
		}
	}
	
	if (g_iInterval <= 0)
	{
		SpawnBoss();
		cTimer = null;
		return Plugin_Stop;
	}
	
	g_iInterval--;
	return Plugin_Continue;
}

void ResetTimer()
{
	delete cTimer;
	CreateCountdownTimer();
	CPrintToChatAll("%t", "Time", g_cInterval.IntValue);
}

/* ---------------------------------TIMER & HUD CORE----------------------------------*/

/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/

public void OnEntityCreated(int ent, const char[] classname)
{
	if (!gEnabled)
		return;
		
	if (StrEqual(classname, "monster_resource"))
		gHPbar = ent;		
	else if ((StrEqual(classname, HORSEMAN) || StrEqual(classname, MONOCULUS) || StrEqual(classname, MERASMUS) || StrEqual(classname, SKELETON)))
	{
		gTrack = ent;
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
		RequestFrame(UpdateBossHealth, EntIndexToEntRef(ent));
	}
	else if (StrEqual(classname, "prop_dynamic"))
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
}

public void OnEntityDestroyed(int ent)
{
	if (!gEnabled)
		return;
		
	if (!IsValidEntity(ent)) 
		return;
		
	if (ent == gTrack)
	{
		gTrack = -1;
		for (int i = 0; i < 2048; i++) 
		{
			if (!IsValidEntity(i)) 
				continue;
				
			if (i == ent)
				continue;
			else 
			{
				gTrack = i;
				break;
			}
		}
		if (gTrack != -1) 
			SDKHook(gTrack, SDKHook_OnTakeDamagePost, OnBossDamaged);
		else
			SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", 0);
	}
	
	for (int i = gData.Length-1; i >= 0; i--)
	{
		ArrayList dReference = gData.Get(i);
		int dEnt = EntRefToEntIndex(dReference.Get(1));
		
		if (ent == dEnt)
		{
			DataPack dMax = dReference.Get(0);
			dMax.Reset();
			int iMax = dMax.ReadCell();
			int index = dReference.Get(2);
			int timed = dReference.Get(3);
			iMax -= 1;
			dMax.Reset();
			dMax.WriteCell(iMax);
			dReference.Set(0, dMax);
			gData.Erase(i);
			
			if (timed)
				g_AutoBoss--;
				
			if (iMax == 0)
			{
				StringMap HashMap = gArray.Get(index);
				char sDSound[256];
				HashMap.GetString("DeathSound", sDSound, sizeof(sDSound));
				
				if (!StrEqual(sDSound, "none", false))
					EmitSoundToAll(sDSound, _, _, _, _, 1.0);
					
				if (timed && GetClientCount(true) >= g_cMinplayers.IntValue && g_AutoBoss == 0)
					ResetTimer();
					
				delete dMax;
			}
			delete dReference;
			break;
		}
	}
}

public void OnPropSpawn(any ref)
{
	int ent = EntRefToEntIndex(ref);
	
	if (!IsValidEntity(ent)) 
		return;
		
	int parent = GetEntPropEnt(ent, Prop_Data, "m_pParent");
	
	if (!IsValidEntity(parent)) 
		return;
		
	char strClassname[64];
	GetEntityClassname(parent, strClassname, sizeof(strClassname));
	if (StrEqual(strClassname, HORSEMAN, false))
	{
		for (int i = gData.Length-1; i >= 0; i--)
		{
			ArrayList dReference = gData.Get(i);
			int dEnt = EntRefToEntIndex(dReference.Get(1));
			int dIndex = dReference.Get(2);
			
			if (parent == dEnt)
			{
				char sWModel[256];
				StringMap HashMap = gArray.Get(dIndex);
				HashMap.GetString("WeaponModel", sWModel, sizeof(sWModel));
				if (strlen(sWModel) != 0)
				{
					if (StrEqual(sWModel, "Invisible"))
						SetEntProp(ent, Prop_Send, "m_fEffects", EF_NODRAW);
					else
					{
						SetEntityModel(ent, sWModel);
						SetEntPropEnt(parent, Prop_Send, "m_hActiveWeapon", ent);
					}
				}
				break;
			}
		}
	}
}

void FindHealthBar()
{
	gHPbar = FindEntityByClassname(-1, "monster_resource");
	
	if (gHPbar == -1)
	{
		gHPbar = CreateEntityByName("monster_resource");
		
		if (gHPbar != -1)
			DispatchSpawn(gHPbar);
	}
}

public Action OnBossDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	UpdateBossHealth(victim);
}

public Action OnClientDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{	
	if (!IsClientInGame(victim)) 
		return Plugin_Continue;
		
	if (!IsValidEntity(attacker)) 
		return Plugin_Continue;
		
	char classname[32];
	GetEntityClassname(attacker, classname, sizeof(classname));
	
	if (StrEqual(classname, HORSEMAN) || StrEqual(classname, MONOCULUS) || StrEqual(classname, MERASMUS) || StrEqual(classname, SKELETON))
	{
		char sDamage[32];
		for (int i = gData.Length-1; i >= 0; i--)
		{
			ArrayList dReference = gData.Get(i);
			int dEnt = EntRefToEntIndex(dReference.Get(1));
			int dIndex = dReference.Get(2);
			
			if (attacker == dEnt)
			{
				StringMap HashMap = gArray.Get(dIndex);
				HashMap.GetString("Damage", sDamage, sizeof(sDamage));
				damage = StringToFloat(sDamage);
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

public void UpdateBossHealth(int ent) 
{
	if (gHPbar == -1 || g_cHealthbar.IntValue == 0 || g_cHealthbar.IntValue == 2)
		return;
	
	if (!IsValidEntity(ent))
	{
		SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", 0);
		return;
	}
	
	int HP = GetEntProp(ent, Prop_Data, "m_iHealth");
	int maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
	float currentHP = HP - maxHP * 0.9;
	
	if (currentHP > 0.0)
	{
		SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", RoundToCeil((float(HP) / float(maxHP / 10)) * 255.9));
		return;
	}
	
	char classname[32];
	GetEntityClassname(ent, classname, sizeof(classname));
	
	if (StrEqual(classname, SKELETON))
	{
		for (int i = gData.Length-1; i >= 0; i--)
		{
			ArrayList dReference = gData.Get(i);
			int dEnt = EntRefToEntIndex(dReference.Get(1));
			if (ent == dEnt) 
			{
				int dIndex = dReference.Get(2);
				char sGnome[8];
				StringMap HashMap = gArray.Get(dIndex);
				HashMap.GetString("Gnome", sGnome, sizeof(sGnome));
				if (StringToInt(sGnome) == 0)
					AcceptEntityInput(ent, "kill");
				break;
			}
		}
	}
	else
	{
		if (HP <= -1)
			SetEntProp(ent, Prop_Data, "m_takedamage", 0);
		SetEntProp(ent, Prop_Data, "m_iHealth", 0);
	}
	SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", 0);
}

/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/

/* ---------------------------------CALL FUNCTIONS------------------------------------*/
void SetEyeballLifetime(int duration)
{
	g_cEyeball_Lifetime.SetInt(duration, false, false);
}

void SetMerasmusLifetime(int duration)
{
	g_cMerasmus_Lifetime.SetInt(duration, false, false);
}
/* ---------------------------------CALL FUNCTIONS------------------------------------*/

/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/
public void SetupMapConfigs(const char[] sFile)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if (!FileExists(sPath))
	{
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	
	KeyValues kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if (!KvGotoFirstSubKey(kv))
	{
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	
	int mapEnabled = 0;
	bool Default = false;
	int tempEnabled = 0;
	float temp_pos[3];
	char requestMap[64], currentMap[64], sPosition[64], tPosition[64];
	GetCurrentMap(currentMap, sizeof(currentMap));
	
	do 
	{
		kv.GetSectionName(requestMap, sizeof(requestMap));
		if (StrEqual(requestMap, currentMap, false))
		{
			mapEnabled = kv.GetNum("Enabled", 0);
			gPos[0] = kv.GetFloat("Position X", 0.0);
			gPos[1] = kv.GetFloat("Position Y", 0.0);
			gPos[2] = kv.GetFloat("Position Z", 0.0);
			kv.GetString("TeleportPosition", sPosition, sizeof(sPosition), SNULL);
			Default = true;
		}
		else if (StrEqual(requestMap, "Default", false))
		{
			tempEnabled = kv.GetNum("Enabled", 0);
			temp_pos[0] = kv.GetFloat("Position X", 0.0);
			temp_pos[1] = kv.GetFloat("Position Y", 0.0);
			temp_pos[2] = kv.GetFloat("Position Z", 0.0);
			kv.GetString("TeleportPosition", tPosition, sizeof(tPosition), SNULL);
		}
	} while kv.GotoNextKey();
	delete kv;
	
	if (Default == false)
	{
		mapEnabled = tempEnabled;
		gPos = temp_pos;
		Format(sPosition, sizeof(sPosition), "%s", tPosition);
	}
	
	float tpos[3];
	if (strlen(sPosition) != 0)
	{
		int ent;
		while ((ent = FindEntityByClassname(ent, "info_target")) != -1)
		{
			if (IsValidEntity(ent))
			{
				char strName[32];
				GetEntPropString(ent, Prop_Data, "m_iName", strName, sizeof(strName));
				if (StrContains(strName, "spawn_loot") != -1)
				{
					AcceptEntityInput(ent, "Kill");
				}
			}
		}
		
		char sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		tpos[0] = StringToFloat(sPos[0]);
		tpos[1] = StringToFloat(sPos[1]);
		tpos[2] = StringToFloat(sPos[2]);
		
		for (int i = 0; i < 4; i++)
		{
			ent = CreateEntityByName("info_target");
			char spawn_name[16];
			Format(spawn_name, sizeof(spawn_name), "%s", i == 0 ? "spawn_loot" : (i == 1 ? "spawn_loot_red" : (i == 2 ? "spawn_loot_blue" : "spawn_boss_alt")));
			SetEntPropString(ent, Prop_Data, "m_iName", spawn_name);
			TeleportEntity(ent, tpos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
		}
	}
	
	if (mapEnabled != 0)
	{
		gEnabled = true;
		if (GetClientCount(true) >= g_cMinplayers.IntValue)
		{
			CreateCountdownTimer();
			CPrintToChatAll("%t", "Time", g_cInterval.IntValue);
		}
	}
	else if (mapEnabled == 0)
		gEnabled = false;
		
	LogMessage("Loaded Map configs successfully."); 
}

public void SetupBossConfigs(const char[] sFile)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if (!FileExists(sPath))
	{
		LogError("[CBS] Error: Can not find map filepath %s", sPath);
		SetFailState("[CBS] Error: Can not find map filepath %s", sPath);
	}
	
	Handle kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if (!KvGotoFirstSubKey(kv))
	{
		LogError("[CBS] Could not read maps file: %s", sPath);
		SetFailState("[CBS] Could not read maps file: %s", sPath);
	}
	
	gArray.Clear();
	char sName[64], sModel[256], sType[32], sBase[16], sScale[16], sWModel[256], sSize[16], sGlow[32], sPosFix[32];
	char sLifetime[32], sPosition[32], sHorde[8], sColor[16], sISound[256], sDSound[256], sHModel[256], sGnome[8];
	char sHatPosFix[32], sHatSize[16], sDamage[32];
	
	do
	{
		KvGetSectionName(kv, sName, sizeof(sName));
		KvGetString(kv, "Model", sModel, sizeof(sModel), SNULL);
		KvGetString(kv, "Type", sType, sizeof(sType));
		KvGetString(kv, "HP Base", sBase, sizeof(sBase), "10000");
		KvGetString(kv, "HP Scale", sScale, sizeof(sScale), "1000");
		KvGetString(kv, "WeaponModel", sWModel, sizeof(sWModel), SNULL);
		KvGetString(kv, "Size", sSize, sizeof(sSize), "1.0");
		KvGetString(kv, "Glow", sGlow, sizeof(sGlow), "0 0 0 0");
		KvGetString(kv, "PosFix", sPosFix, sizeof(sPosFix), "0.0");
		KvGetString(kv, "Lifetime", sLifetime, sizeof(sLifetime), "120");
		KvGetString(kv, "Position", sPosition, sizeof(sPosition), SNULL);
		KvGetString(kv, "Horde", sHorde, sizeof(sHorde), "1");
		KvGetString(kv, "Color", sColor, sizeof(sColor), SNULL);
		KvGetString(kv, "IntroSound", sISound, sizeof(sISound), INTRO_SND);
		KvGetString(kv, "DeathSound", sDSound, sizeof(sDSound), DEATH_SND);
		KvGetString(kv, "HatModel", sHModel, sizeof(sHModel), SNULL);
		KvGetString(kv, "Gnome", sGnome, sizeof(sGnome), "0");
		KvGetString(kv, "HatPosFix", sHatPosFix, sizeof(sHatPosFix), "0.0");
		KvGetString(kv, "HatSize", sHatSize, sizeof(sHatSize), "1.0");
		KvGetString(kv, "Damage", sDamage, sizeof(sDamage), "100.0");
		
		if (StrContains(sName, " ") != -1)
		{
			LogError("[CBS] Error: Boss names should not have spaces, please replace spaces with underscore '_'");
			SetFailState("[CBS] Error: Boss names should not have spaces, please replace spaces with underscore '_'");
		}
		
		bool bHorseman = StrEqual(sType, HORSEMAN);
		bool bMonoculus = StrEqual(sType, MONOCULUS);
		bool bMerasmus = StrEqual(sType, MERASMUS);
		bool bSkeleton = StrEqual(sType, SKELETON);
		
		if (!bHorseman && !bMonoculus && !bMerasmus && !bSkeleton)
		{
			LogError("[CBS] Boss type is undetermined, please check the boss type spelling again.");
			SetFailState("[CBS] Boss type is undetermined, please check the boss type spelling again.");
		}
		
		if (!bSkeleton)
		{
			if (!StrEqual(sHorde, "1"))
			{
				LogError("[CBS] Horde mode only works for boss type: tf_zombie.");
				SetFailState("[CBS] Horde mode only works for boss type: tf_zombie.");
			}
			if (strlen(sColor))
			{
				LogError("[CBS] Color mode only works for boss type: tf_zombie.");
				SetFailState("[CBS] Color mode only works for boss type: tf_zombie.");
			}
			if (!StrEqual(sGnome, "0"))
			{
				LogError("[CBS] Gnome only works for boss type: tf_zombie.");
				SetFailState("[CBS] Gnome only works for boss type: tf_zombie.");
			}
		}
		
		if (bMonoculus)
		{
			SetEyeballLifetime(9999999);
			if (strlen(sModel))
			{
				LogError("[CBS] Can not apply custom model to monoculus.");
				SetFailState("[CBS] Can not apply custom model to monoculus.");
			}
		}
		
		if (bMerasmus)
			SetMerasmusLifetime(9999999);
		
		if (strlen(sWModel))
		{
			if (!bHorseman)
			{
				LogError("[CBS] Weapon model can only be changed on boss type: headless_hatman");
				SetFailState("[CBS] Weapon model can only be changed on boss type: headless_hatman");
			}
			else if (!StrEqual(sWModel, "Invisible"))
			{
				PrecacheModel(sWModel, true);
			}
		}
		
		if (strlen(sModel))
			PrecacheModel(sModel, true);
			
		if (strlen(sHModel))
			PrecacheModel(sHModel, true);
			
		PrecacheSound(sISound);
		PrecacheSound(sDSound);
		
		StringMap HashMap = new StringMap();
		HashMap.SetString("Name", sName, false);
		HashMap.SetString("Model", sModel, false);
		HashMap.SetString("Type", sType, false);
		HashMap.SetString("Base", sBase, false);
		HashMap.SetString("Scale", sScale, false);
		HashMap.SetString("WeaponModel", sWModel, false);
		HashMap.SetString("Size", sSize, false);
		HashMap.SetString("Glow", sGlow, false);
		HashMap.SetString("PosFix", sPosFix, false);
		HashMap.SetString("Lifetime", sLifetime, false);
		HashMap.SetString("Position", sPosition, false);
		HashMap.SetString("Horde", sHorde, false);
		HashMap.SetString("Color", sColor, false);
		HashMap.SetString("IntroSound", sISound, false);
		HashMap.SetString("DeathSound", sDSound, false);
		HashMap.SetString("HatModel", sHModel, false);
		HashMap.SetString("Gnome", sGnome, false);
		HashMap.SetString("HatPosFix", sHatPosFix, false);
		HashMap.SetString("HatSize", sHatSize, false);
		HashMap.SetString("Damage", sDamage, false);
		gArray.Push(HashMap);
		
		char command[64];
		Format(command, sizeof(command), "sm_%s", sName);
		AddCommandListener(SpawnBossCommand, command);
	} while (KvGotoNextKey(kv));
	
	delete kv;
	LogMessage("Custom Boss Spawner Configuration has loaded successfully."); 
}

public void SetupDownloads(const char[] sFile)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if (!FileExists(sPath))
	{
		LogError("[Boss] Error: Can not find download file %s", sPath);
		SetFailState("[Boss] Error: Can not find download file %s", sPath);
	}
	
	File file = OpenFile(sPath, "r");
	char buffer[256], fName[128], fPath[256];
	while (!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer)))
	{
		int i = -1;
		i = FindCharInString(buffer, '\n', true);
		
		if(i != -1) 
			buffer[i] = '\0';
			
		TrimString(buffer);
		
		if (!DirExists(buffer))
		{
			LogError("[Boss] Error: '%s' directory can not be found.", buffer);
			SetFailState("[Boss] Error: '%s' directory can not be found.", buffer);
		}
		
		int isMaterial = 0;
		if (StrContains(buffer, "materials/", true) != -1 || StrContains(buffer, "materials\\", true) != -1)
			isMaterial = 1;
			
		DirectoryListing sDir = OpenDirectory(buffer, true);
		while (sDir.GetNext(fName, sizeof(fName)))
		{
			if (StrEqual(fName, ".") || StrEqual(fName, "..")) 
				continue;
			if (StrContains(fName, ".ztmp") != -1) 
				continue;
			if (StrContains(fName, ".bz2") != -1)
				continue;
				
			Format(fPath, sizeof(fPath), "%s/%s", buffer, fName);
			AddFileToDownloadsTable(fPath);
			
			if (isMaterial == 1) 
				continue;
			if (StrContains(fName, ".vtx") != -1)
				continue;
			if (StrContains(fName, ".vvd") != -1)
				continue;
			if (StrContains(fName, ".phy") != -1)
				continue;
				
			PrecacheGeneric(fPath, true);
		}
		delete sDir;
	}
	delete file;
}
/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/
