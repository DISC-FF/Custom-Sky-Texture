#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>
#include <filenetwork>

#pragma newdecls required

KeyValues SkyKv;
Cookie CookieMap;
ConVar SkyCvar;
char MapName[64];
bool CanQueue[36];
bool Downloading[36];

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
			if(SkyKv.JumpToKey("download"))
			{
				CanQueue[client] = true;
				
				char buffer[PLATFORM_MAX_PATH];
				Format(buffer, sizeof(buffer), "materials/skybox/%s_%d.txt", skybox, GetSteamAccountID(client, false));
				
				DataPack pack = new DataPack();
				pack.WriteString(skybox);
				FileNet_RequestFile(client, buffer, CheckForFile, pack);
			}
			else
			{
				SkyCvar.ReplicateToClient(client, skybox);
			}
		}
		else
		{
			CookieMap.Set(client, NULL_STRING);
		}
	}
}

public void OnClientDisconnect(int client)
{
	CanQueue[client] = false;
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
			if(!skybox[0])
			{
				CookieMap.Set(client, NULL_STRING);
				SkyCvar.GetString(skybox, sizeof(skybox));
				SkyCvar.ReplicateToClient(client, skybox);
			}
			else
			{
				SkyKv.Rewind();
				if(SkyKv.JumpToKey(skybox) && SkyKv.JumpToKey("download"))
				{
					CanQueue[client] = true;
					
					char buffer[PLATFORM_MAX_PATH];
					Format(buffer, sizeof(buffer), "materials/skybox/%s_%d.txt", skybox, GetSteamAccountID(client, false));
					
					DataPack pack = new DataPack();
					pack.WriteString(skybox);
					FileNet_RequestFile(client, buffer, CheckForFile, pack);
				}
				else
				{
					CookieMap.Set(client, skybox);
					SkyCvar.ReplicateToClient(client, skybox);
					HasOverride[client] = true;
				}
			}
			
			MainMenu(client, choice);
		}
	}
	return 0;
}

public void CheckForFile(int client, const char[] file, int id, bool success, DataPack pack)
{
	static char buffer[PLATFORM_MAX_PATH];
	
	if(success)
	{
		if(!DeleteFile(file, true))
		{
			Format(buffer, sizeof(buffer), "download/%s", file);
			if(!DeleteFile(buffer))
				LogError("Failed to delete file \"%s\"", file);
		}
	}
	
	bool delet = true;
	
	if(CanQueue[client])
	{
		if(success)
		{
			pack.Reset();
			pack.ReadString(buffer, sizeof(buffer));
			CookieMap.Set(client, buffer);
			SkyCvar.ReplicateToClient(client, buffer);
		}
		else if(Downloading[client])
		{
			PrintToChat(client, "[SM] A sky texture is already downloading!");
		}
		else
		{
			PrintToChat(client, "[SM] Downloading sky texture...");
			
			pack.Reset();
			pack.ReadString(buffer, sizeof(buffer));
			
			SkyKv.Rewind();
			if(SkyKv.JumpToKey(buffer) && SkyKv.JumpToKey("download") && SkyKv.GotoFirstSubKey(false))
			{
				bool failed;
				
				do
				{
					SkyKv.GetSectionName(buffer, sizeof(buffer));
					if(FileNet_SendFile(client, buffer, FinishBaseFile))
					{
						Downloading[client]++;
					}
					else
					{
						failed = true;
						LogError("Failed to queue file \"%s\" to client", buffer);
					}
				}
				while(SkyKv.GotoNextKey(false));
				
				if(!failed)
				{
					File filec = OpenFile(file, "wt");
					filec.WriteLine("Used for file checks for DISC-FF servers");
					filec.Close();
					
					if(FileNet_SendFile(client, file, FinishCheckFile, pack))
					{
						Downloading[client]++;
						delet = false;
					}
					else
					{
						LogError("Failed to queue file \"%s\" to client", file);
						if(!DeleteFile(file))
							LogError("Failed to delete file \"%s\"", file);
					}
				}
			}
		}
	}
	
	if(delet)
		delete pack;
}

public void FinishBaseFile(int client, const char[] file, bool success)
{
	Downloading[client]--;
	
	if(CanQueue[client] && !success)
		LogError("Failed to send file \"%s\" to client", file);
}

public void FinishCheckFile(int client, const char[] file, bool success, DataPack pack)
{
	Downloading[client]--;
	
	if(CanQueue[client])
	{
		if(success)
		{
			char buffer[64];
			
			pack.Reset();
			pack.ReadString(buffer, sizeof(buffer));
			
			SkyKv.Rewind();
			if(SkyKv.JumpToKey(buffer))
				SkyKv.GetString("name", buffer, sizeof(buffer), buffer);
			
			PrintToChat(client, "[SM] Sky texture \"%s\" finished downloading", buffer);
		}
		else
		{
			LogError("Failed to send file \"%s\" to client", file);
		}
	}
	
	if(!DeleteFile(file))
		LogError("Failed to delete file \"%s\"", file);
	
	delete pack;
}
