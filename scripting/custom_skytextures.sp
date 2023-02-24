#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>

#pragma newdecls required

KeyValues SkyKv;
Cookie CookieMap;
ConVar SkyCvar;
char MapName[64];

public Plugin myinfo =
{
	name		=	"Sky Textures",
	author		=	"Batfoxkid",
	description	=	"Per-client sv_skynamme",
	version		=	"manual"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_sky", Command, "Change your Sky Texture", FCVAR_HIDDEN);
	RegConsoleCmd("sm_skyname", Command, "Change your Sky Texture");
	SkyCvar = FindConVar("sv_skyname");
}

public void OnConfigsExecuted()
{
	delete SkyKv;
	delete CookieMap;
	
	GetCurrentMap(MapName, sizeof(MapName));
	int pos = FindCharInString(MapName, '_', true);
	if(pos != -1)
		MapName[pos] = '\0';
	
	char buffer[PLATFORM_MAX_PATH];
	
	Format(buffer, sizeof(buffer), "skytexture_%s", MapName);
	CookieMap = new Cookie(buffer, "", CookieAccess_Private);
	
	BuildPath(Path_SM, buffer, sizeof(buffer), "data/skytextures.cfg");
	
	SkyKv = new KeyValues("SkyListing");
	SkyKv.ImportFromFile(buffer);
}

public void OnClientCookiesCached(int client)
{
	char skybox[64];
	CookieMap.Get(client, skybox, sizeof(skybox));
	if(skybox[0])
	{
		SkyKv.Rewind();
		if(SkyKv.JumpToKey(skybox))
		{
			SkyCvar.ReplicateToClient(client, skybox);
		}
		else
		{
			CookieMap.Set(client, NULL_STRING);
		}
	}
}
public Action Command(int client, int args)
{
	if(client)
		MainMenu(client, 0);
	
	return Plugin_Handled;
}

void MainMenu(int client, int page)
{
	Menu menu = new Menu(Handler);
	menu.SetTitle("Sky Texture for %s\n ", MapName);
	
	menu.AddItem(NULL_STRING, "Default");
	
	SkyKv.Rewind();
	SkyKv.GotoFirstSubKey();
	
	char data[64], display[64];
	
	do
	{
		SkyKv.GetSectionName(data, sizeof(data));
		SkyKv.GetString("name", display, sizeof(display), data);
		menu.AddItem(data, display);
	}
	while(SkyKv.GotoNextKey());
	
	menu.DisplayAt(client, page / 7 * 7, MENU_TIME_FOREVER);
}

public int Handler(Menu menu, MenuAction action, int client, int choice)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			char skybox[64];
			menu.GetItem(choice, skybox, sizeof(skybox));
			if(skybox[0])
			{
				CookieMap.Set(client, skybox);
				SkyCvar.ReplicateToClient(client, skybox);
			}
			else
			{
				CookieMap.Set(client, NULL_STRING);
				SkyCvar.GetString(skybox, sizeof(skybox));
				SkyCvar.ReplicateToClient(client, skybox);
			}
			
			MainMenu(client, choice);
		}
	}
	return 0;
}