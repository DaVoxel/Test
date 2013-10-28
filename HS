using System;
using System.Collections.Generic;
using System.Text;
using InfinityScript;

namespace HideSeek
{
    public class Hide_Seek : BaseScript
    {
        public static string[] modellist;
        public static string mapname;
        int HiderTimer = 25;
        HudElem HiderTimerIcon;
        HudElem HiderTimerText;
        HudElem globalTimer;
        int SeekerHealth = 280;

        private unsafe void PatchMatchRules()
        {
            *(byte*)0x04A2120 = 0xB8;
            *(int*)0x04A2121 = 0;
            *(int*)0x04A2125 = 1351651472;
        }

        public override void OnPlayerDamage(Entity player, Entity inflictor, Entity attacker, int damage, int dFlags, string mod, string weapon, Vector3 point, Vector3 dir, string hitLoc)
        {
            if (mod == "MOD_FALLING")
                player.Health += damage;
        }

        public override void OnPlayerKilled(Entity player, Entity inflictor, Entity attacker, int damage, string mod, string weapon, Vector3 dir, string hitLoc)
        {
            DeleteModel(player);
            player.SetField("hnsType", string.Empty);
            if (player.HasField("MenuOpen") && player.GetField<int>("MenuOpen") == 1)
                player.Notify("smoke");
        }

        public Hide_Seek()
        {
            PatchMatchRules();
            Call("precacheShader", "iw5_cardtitle_elite_10");
            Call("precacheShader", "iw5_cardtitle_crackin_skulls");
            Call("precacheShader", "iw5_cardtitle_elite_01");
            Call("precacheShader", "cardicon_skull_black");
            mapname = Call<string>("getdvar", "mapname");
            Modellist.SetModellist();

            PlayerDisconnected += new Action<Entity>(entity =>
                {
                    CustomHud.UpdateHud(entity, 1);

                    DeleteModel(entity);
                });

            PlayerConnected += new Action<Entity>(entity =>
            {
                entity.Call("notifyonplayercommand", "tab", "+scores");
                entity.Call("notifyonplayercommand", "-tab", "-scores");
                entity.Call("notifyonplayercommand", "3", "+actionslot 3");
                entity.SetField("ThirdPerson", "0");
                entity.SetField("HasSpawned", 0);

                entity.OnNotify("3", ent =>
                    {
                        string value = ent.GetField<string>("ThirdPerson") == "0" ? "1" : "0";
                        ent.SetField("ThirdPerson", value);
                        ent.SetClientDvar("cg_thirdperson", value);
                        ent.SetClientDvar("cg_thirdPersonRange", "170");
                    });

                entity.SpawnedPlayer += new Action(() =>
                    {
                        GameLog.Write("spawned");
                        entity.SetField("HasSpawned", 1);
                        OnSpawned(entity);
                    });

                InitSpin(entity);

                entity.OnNotify("reset_outcome", ent =>
                {
                    DeleteModel(ent);
                    if (ent.HasField("MenuOpen") && ent.GetField<int>("MenuOpen") == 1)
                        ent.Notify("smoke");
                });

                entity.OnNotify("weapon_change", (ent, newWeapon) =>
                    {
                        if ((string)newWeapon == "briefcase_bomb_mp")
                        {
                            ent.TakeWeapon("briefcase_bomb_mp");
                            ent.Call("iprintlnbold", "Don't try to plant, bitch");
                        }
                    });

                Menu.MenuInit(entity);
                entity.SetField("hnsType", string.Empty);
                CustomHud.HudInit(entity);

                entity.Call("notifyonplayercommand", "5", "+actionslot 5");
                entity.SetField("showingInfo", 0);
                entity.OnNotify("5", ent =>
                {
                    if (ent.HasField("showingInfo") && ent.GetField<int>("showingInfo") == 0)
                        ShowInfo(ent);
                });

                entity.Call("notifyonplayercommand", "4", "+actionslot 4");
                entity.OnNotify("4", ent =>
                {
                    if (!entity.IsAlive)
                        return;
                    if (ent.GetField<string>("sessionteam") == GetHiderTeam())
                        ChangeModel(ent);
                    else
                        _Utility.Silencer(ent);

                });

                entity.Call("notifyonplayercommand", "6", "+actionslot 6");
                entity.SetField("SeekerSensor", 1);
                entity.OnNotify("6", ent =>
                {
                    entity.SetField("SeekerSensor", entity.GetField<int>("SeekerSensor") == 0 ? 1 : 0);
                });
            });

            //dirty fix for bug in AfterDelay (code is executed before updating time in AfterDelay Processor (ProcessTimers()) -> code executed too early
            AfterDelay(50, () =>
                {
                    AfterDelay(200, () =>
                    {
                        SetTeamNames();
                        CheckBonusTime();
                        SetDvars();
                        HiderTimerIcon = HudElem.NewHudElem();
                        HiderTimerIcon.Parent = HudElem.UIParent;
                        HiderTimerIcon.SetPoint("LEFT", "LEFT", 5, -10);
                        HiderTimerIcon.HideWhenInMenu = true;
                        HiderTimerIcon.Foreground = false;
                        HiderTimerIcon.SetShader("iw5_cardtitle_elite_10", 180, 30);
                        HiderTimerIcon.Alpha = 0f;
                        HiderTimerText = HudElem.CreateServerFontString("default", 1.5f);
                        HiderTimerText.SetPoint("LEFT", "LEFT", 30, -10);
                        HiderTimerText.HideWhenInMenu = true;
                        HiderTimerText.Foreground = true;
                    });
                });

            OnNotify("prematch_over", () =>
                {
                    HideTimer();
                    CustomHud.ShowGametype();
                    CustomHud.showAliveHud();
                    ShowAlive();
                    globalTimer = HudElem.NewHudElem();
                    globalTimer.Parent = HudElem.UIParent;
                    globalTimer.SetPoint("LEFT", "BOTTOMLEFT", 15, -66);
                    globalTimer.Font = "bold";
                    globalTimer.FontScale = 1.5f;
                    globalTimer.HideWhenInMenu = true;
                    globalTimer.Alpha = 1f;
                    globalTimer.Call("settimer", (float.Parse(Call<string>("getdvar", "scr_sd_timelimit")) * 60) - 1f);
                    OnInterval(1000, () =>
                        {
                            if (globalTimer == null)
                                return false;
                            if (GetTimeLeft() < 1)
                                return false;

                            if (GetTimeLeft() < 10000)
                                globalTimer.SetField("color", new Vector3(1f, 0.23f, 0f));
                            else
                                globalTimer.SetField("color", new Vector3(1f, 1f, 1f));

                            return true;
                        });
                    for (int i = 0; i < 18; i++)
                    {
                        Entity player = Call<Entity>("getEntByNum", i);
                        if (player != null && player.IsPlayer && player.IsAlive)
                        {
                            if (player.HasField("HasSpawned") && player.GetField<int>("HasSpawned") == 0)
                            {
                                OnSpawned(player);
                            }
                        }
                    }
                });
            OnNotify("reset_outcome", () =>
                {
                    globalTimer.Call("destroy");
                });

            for (int i = 0; i < 2047; i++)
            {
                Entity ent = Call<Entity>("getEntByNum", i);

                if (ent != null)
                {
                    string classname = ent.GetField<string>("classname");
                    if (classname == "misc_turret")
                        ent.Call("delete");
                }
            }
        }

        private void SetDvars()
        {
            Call("setdvar", "g_hardcore", "1");
            Call("setdynamicdvar", "scr_game_hardpoints", 0);
            Call("setdvar", "scr_game_spectatetype", 2);
            Call("setdvar", "scr_sd_winlimit", "6");
            Call("setdvar", "scr_sd_roundswitch", "2");
            Call("setdvarifuninitialized", "scr_hns_hidetime", 25);
            HiderTimer = Call<int>("getdvarint", "scr_hns_hidetime");
            Call("setdvarifuninitialized", "scr_hns_timelimit", 3);
            Call("setdvar", "scr_sd_timelimit", Call<string>("getdvar", "scr_hns_timelimit"));
            Call("setdvarifuninitialized", "scr_hns_seekerhealth", 280);
            SeekerHealth = Call<int>("getdvarint", "scr_hns_seekerhealth");
            Call("setdvar", "scr_game_matchstarttime", "1");
            Call("setdvar", "scr_game_playerwaittime", "3");
            Call("setdvar", "scr_hardpoint_allowuav", "0");
            Call("setdvarifuninitialized", "scr_hns_seekersensor", 0);
        }

        private void OnSpawned(Entity entity)
        {
            string team = entity.GetField<string>("sessionteam");
            string teamchar = Call<string>("getmapcustom", team + "char");
            string snd = Call<string>("tablelookup", "mp/factionTable.csv", 0, teamchar, 7);
            GameLog.Write("snd is: " + snd);
            snd += "spawn_music";
            entity.Call("stoplocalsound", snd);
            entity.AfterDelay(500, ent =>
            {
                if (team == GetHiderTeam())
                    InitHider(ent);
                else if (team == _Utility.GetOtherTeam(GetHiderTeam()))
                    InitSeeker(ent);
                CustomHud.OnSpawned(ent);
            });
        }

        private void CheckBonusTime()
        {
            OnInterval(5000, () =>
                {
                    string hiders = GetHiderTeam();
                    int hiderCount = GetTeamCount(hiders);
                    if (hiderCount < 4)
                        return true;
                    if (Call<int>("getteamplayersalive", hiders) > (int)Math.Ceiling((float)hiderCount/3))
                        return true;
                    float OldTime = float.Parse(Call<string>("getdvar", "scr_sd_timelimit"));
                    Call("setdvar", "scr_sd_timelimit", Convert.ToString((OldTime + 0.5f), System.Globalization.CultureInfo.InvariantCulture.NumberFormat));
                    int timePassed = GetTimePassed();
                    float tP = (float)timePassed / 1000;
                    globalTimer.Call("settimer", ((OldTime + 0.5f) * 60) - (float)Math.Ceiling(tP) + 2.7f);//+2.7 because ???? mw3 shit
                    HudElem txt1 = HudElem.CreateServerFontString("default", 1.45f);
                    txt1.SetPoint("CENTER", "MIDDLE", 0, -165);
                    txt1.Call("settext", "+30 Seconds added!");
                    HudElem txt2 = HudElem.CreateServerFontString("default", 1.2f);
                    txt2.SetPoint("CENTER", "MIDDLE", 0, -140);
                    txt2.Call("settext", "Only a few Hiders left");
                    HudElem Icon = HudElem.NewHudElem();
                    Icon.Parent = HudElem.UIParent;
                    Icon.SetPoint("CENTER", "MIDDLE", 0, -165);
                    Icon.Foreground = false;
                    Icon.SetShader("iw5_cardtitle_elite_01", 170, 35);                    

                    AfterDelay(6000, () =>
                        {
                            txt1.Call("fadeovertime", 2f);
                            txt1.Alpha = 0f;
                            txt2.Call("fadeovertime", 2f);
                            txt2.Alpha = 0f;
                            Icon.Call("fadeovertime", 2f);
                            Icon.Alpha = 0f;
                            AfterDelay(2000, () =>
                                {
                                    txt1.Call("destroy");
                                    txt2.Call("destroy");
                                    Icon.Call("destroy");
                                });
                        });

                    for (int i = 0; i < 18; i++)
                    {
                        Entity player = Call<Entity>("getEntByNum", i);
                        if (player != null && player.IsPlayer)
                            player.Call("playLocalSound", "mp_time_running_out_losing");
                    }
                    
                    return false;
                });
        }

        private void HideTimer()
        {
            HiderTimerIcon.Alpha = 1f;
            OnInterval(1000, () =>
            {
                HiderTimer--;
                HiderTimerText.Call("settext", "Seekers released in: " + HiderTimer);

                for (int i = 0; i < 18; i++)
                {
                    Entity ent = Call<Entity>("getEntByNum", i);
                    if (ent != null && ent.IsPlayer)
                    {
                        string team = ent.GetField<string>("sessionteam");
                        if (team == GetHiderTeam())
                        {
                            if (HiderTimer > 0)
                            {
                                ent.Call("freezeControls", false);
                                ent.Call("setMoveSpeedScale", 2.6f);
                                ent.Call("setperk", "specialty_longersprint", "1");
                            }
                            else
                            {
                                ent.Call("setMoveSpeedScale", 1f);
                                ent.Call("unsetperk", "specialty_longersprint");
                            }
                        }
                        else if (team == _Utility.GetOtherTeam(GetHiderTeam()))
                        {
                            if (HiderTimer > 0)
                            {
                                ent.Call("freezeControls", true);
                                ent.Call("VisionSetNakedForPlayer", "blacktest", 0);

                                ent.SetField("health", ent.GetField<int>("maxhealth"));
                                ent.Call("hide");
                            }
                            else
                            {
                                ent.Call("VisionSetNakedForPlayer", mapname, 0);
                                ent.Call("freezeControls", false);
                                ent.Call("show");
                            }
                        }
                    }
                }

                if (HiderTimer < 1)
                {
                    if (HiderTimerText != null)
                        HiderTimerText.Call("destroy");
                    if (HiderTimerIcon != null)
                        HiderTimerIcon.Call("destroy");
                    ShowRelease();
                    return false;
                }

                return true;
            });
        }

        private void InitHider(Entity ent)
        {
            ent.SetField("hnsType", "hider");
            ent.Call("clearperks");
            ent.TakeAllWeapons();
            ent.Call("setPerk", "specialty_quieter", "1");
            ent.Call("setPerk", "specialty_falldamage", "0");
            ent.Call("setPerk", "specialty_coldblooded", "1");
            ent.Call("giveWeapon", "iw5_deserteagle_mp_tactical", 0, false);
            ent.Call("switchToWeaponImmediate", "iw5_deserteagle_mp_tactical");
            ent.Call("SetWeaponAmmoClip", "iw5_deserteagle_mp_tactical", 0);
            ent.Call("SetWeaponAmmoStock", "iw5_deserteagle_mp_tactical", 0);
            ent.Call("disableweaponpickup");
            ent.Call("VisionSetNakedForPlayer", mapname, 1);

            ent.Call("notifyonplayercommand", "F", "+activate");
            ent.Call("notifyonplayercommand", "-F", "-activate");
            ent.Call("notifyonplayercommand", "E", "+melee_zoom");
            ent.Call("notifyonplayercommand", "G", "+frag");
            ent.Call("notifyonplayercommand", "-G", "-frag");
            ent.SetClientDvar("lowAmmoWarningNoAmmoColor2", "0 0 0 0");
            ent.SetClientDvar("lowAmmoWarningNoAmmoColor1", "0 0 0 0");
            ent.SetClientDvar("lowAmmoWarningNoReloadColor2", "0 0 0 0");
            ent.SetClientDvar("lowAmmoWarningNoReloadColor1", "0 0 0 0");
            ent.SetClientDvar("lowAmmoWarningColor2", "0 0 0 0");
            ent.SetClientDvar("lowAmmoWarningColor1", "0 0 0 0");

            Entity newent = Call<Entity>("spawn", "script_model", ent.Origin);
            ent.SetField("CustomModel", newent);
            ent.SetField("curModel", 0);
            ent.SetField("rotSide", 1);
            ent.SetField("StopRot", 0);
            ent.SetField("RotSpeed", 0f);
            ent.SetField("health", 100);
            ent.SetField("maxhealth", 100);

            newent.SetField("ZOffset", 0);
            ChangeModel(ent);
            ent.Call("hide");

            Menu.CreateMenu(ent);
            Menu.ResetColors(ent, 0);

            ent.OnInterval(45, entity =>
                {
                    if (entity.IsAlive == false)
                        return false;
                    if (entity.GetField<Entity>("CustomModel") == null || entity.GetField<Entity>("CustomModel") == entity)
                        return false;
                    Vector3 pos = entity.Origin;
                    if (newent.GetField<int>("ZOffset") != 0)
                        pos.Z += newent.GetField<int>("ZOffset");
                    newent.Origin = pos;
                    return true;
                });
        }

        private void InitSpin(Entity ent)
        {
            ent.OnNotify("F", entity =>
            {
                if (entity.GetField<string>("sessionteam") != GetHiderTeam())
                    return;
                ent.SetField("RotSpeed", 2.5f);
                SpinModel(entity);
            });
            ent.OnNotify("-F", entity =>
            {
                if (entity.GetField<string>("sessionteam") != GetHiderTeam())
                    return;
                entity.SetField("StopRot", 1);
            });

            ent.OnNotify("G", entity =>
            {
                if (entity.GetField<string>("sessionteam") != GetHiderTeam())
                    return;
                ent.SetField("RotSpeed", 10f);
                SpinModel(entity);
            });
            ent.OnNotify("-G", entity =>
            {
                if (entity.GetField<string>("sessionteam") != GetHiderTeam())
                    return;
                entity.SetField("StopRot", 1);
            });

            ent.OnNotify("E", entity =>
                {
                    if (entity.GetField<string>("sessionteam") != GetHiderTeam())
                        return;
                    int oldSide = entity.GetField<int>("rotSide");
                    entity.SetField("rotSide", oldSide == 1 ? 2 : 1);
                });
        }

        private void SpinModel(Entity ent)
        {
            ent.OnInterval(100, player =>
            {
                if (player.GetField<int>("StopRot") == 1)
                {
                    player.SetField("StopRot", 0);
                    return false;
                }
                int side = player.GetField<int>("rotSide");
                float speed = player.GetField<float>("rotSpeed");

                if (side == 2)
                    speed = -speed;
                Entity newent = player.GetField<Entity>("CustomModel");
                if (newent != player)
                    newent.Call("rotateyaw", speed, 0.01f);

                return true;
            });
        }

        private void DeleteModel(Entity entity)
        {
            if (entity == null)
                return;
            CustomHud.UpdateHud(entity, 2);
            if (!entity.HasField("CustomModel") || entity.GetField<Entity>("CustomModel") == entity)
                return;
            Entity new_ent = entity.GetField<Entity>("CustomModel");
            if (new_ent == null)
                return;
            new_ent.Call("delete");
            entity.SetField("CustomModel", entity);
        }

        public static void ChangeModel(Entity ent)
        {
            if (ent==null || !ent.HasField("CustomModel"))
                return;
            Entity newent = ent.GetField<Entity>("CustomModel");
            if (newent == null || newent == ent)
                return;
            int curModel = ent.GetField<int>("curModel");
            newent.Call("setModel", modellist[curModel]);
            if (modellist[curModel] == "hanging_dead_paratrooper01")
                newent.SetField("ZOffset", 75);
            else if (modellist[curModel] == "com_propane_tank02_small")
                newent.SetField("ZOffset", 50);
            else if (modellist[curModel] == "com_propane_tank02")
                newent.SetField("ZOffset", 55);
            else if (modellist[curModel] == "bw_bbq_sign_diamond")
                newent.SetField("ZOffset", 65);
            else
                newent.SetField("ZOffset", 0);

            if (curModel + 1 == modellist.Length)
                curModel = -1;
            ent.SetField("curModel", curModel + 1);
        }

        private void InitSeeker(Entity ent)
        {
            ent.SetField("hnsType", "seeker");
            ent.SetField("health", 280);
            ent.SetField("maxhealth", 280);
            ent.Call("clearperks");
            ent.Call("setperk", "specialty_longersprint", "1");
            ent.Call("setPerk", "specialty_coldblooded", "1");
            ent.Call("setPerk", "specialty_lightweight", "1");

            if (Call<int>("getdvarint", "scr_hns_seekersensor") != 0)
                SeekerSensor(ent);
        }

        private void SeekerSensor(Entity ent)
        {
            int Counter = 0;
            int iVal = 3;
            ent.OnInterval(1000, entity =>
                {
                    if (!entity.IsAlive || !entity.HasField("hnsType") || entity.GetField<string>("hnsType") != "seeker")
                        return false;
                    if (entity.GetField<int>("SeekerSensor") == 0)
                    {
                        Counter = 0;
                        return true;
                    }
                    Counter++;
                    if (Counter >= iVal)
                    {
                        Counter = 0;
                        entity.Call("playlocalsound", "scrambler_beep");
                    }
                    int Closest = GetClosestPlayerDistance(entity.Origin);
                    if (Closest <= 500)
                        iVal = 1;
                    else if (Closest <= 1000)
                        iVal = 3;
                    else if (Closest <= 2000)
                        iVal = 4;
                    else
                        iVal = 6;
                    return true;
                });
        }

        private int GetClosestPlayerDistance(Vector3 start)
        {
            int Distance = 99999;
            for (int i = 0; i < 18; i++)
            {
                Entity player = Call<Entity>("getEntByNum", i);
                if (player != null && player.IsPlayer && player.IsAlive)
                {
                    if (!player.HasField("hnsType") || player.GetField<string>("hnsType") != "hider")
                        continue;
                    float _dist = Call<float>("distance", start, player.Origin);
                    if (_dist < Distance)
                        Distance = Convert.ToInt32(_dist);
                }
            }

            return Distance;
        }

        private void ShowAlive()
        {
            HudElem SeekersAlive = HudElem.CreateServerFontString("default", 1.4f);
            SeekersAlive.Foreground = true;
            SeekersAlive.HideWhenInMenu = true;
            SeekersAlive.SetPoint("LEFT", "BOTTOMLEFT", 50, -25);
            int Seekers = -1;

            OnInterval(500, () =>
                {
                    int sAlive = Call<int>("getteamplayersalive", _Utility.GetOtherTeam(GetHiderTeam()));
                    if (sAlive != Seekers)
                    {
                        Seekers = sAlive;
                        SeekersAlive.Call("settext", "Seekers alive: " + Seekers);
                    }
                    return true;
                });

            HudElem HidersAlive = HudElem.CreateServerFontString("default", 1.4f);
            HidersAlive.Foreground = true;
            HidersAlive.HideWhenInMenu = true;
            HidersAlive.SetPoint("LEFT", "BOTTOMLEFT", 50, -45);
            int Hiders = -1;

            OnInterval(500, () =>
            {
                int hAlive = Call<int>("getteamplayersalive", GetHiderTeam());
                if (hAlive != Hiders)
                {
                    Hiders = hAlive;
                    HidersAlive.Call("settext", "Hiders alive: " + Hiders);
                }
                return true;
            });
        }

        private void ShowRelease()
        {
            HudElem ReleaseTxt = HudElem.CreateServerFontString("default", 2.1f);
            ReleaseTxt.SetPoint("CENTER", "CENTER", 0, -170);
            ReleaseTxt.SetField("glowcolor", new Vector3(1f, 0f, 0f));
            ReleaseTxt.SetField("color", new Vector3(0.007f, 0f, 0f));
            ReleaseTxt.HideWhenInMenu = true;
            ReleaseTxt.GlowAlpha = 1f;
            ReleaseTxt.Foreground = true;
            ReleaseTxt.Call("settext", "Seekers released!");

            HudElem ReleaseIcon = HudElem.NewHudElem();
            ReleaseIcon.Parent = HudElem.UIParent;
            ReleaseIcon.SetPoint("CENTER", "CENTER", 0, -165);
            ReleaseIcon.HideWhenInMenu = true;
            ReleaseIcon.Foreground = false;
            ReleaseIcon.SetShader("iw5_cardtitle_crackin_skulls", 200, 40);

            AfterDelay(5000, () =>
                {
                    ReleaseIcon.Call("fadeovertime", 2f);
                    ReleaseIcon.Alpha = 0f;
                    ReleaseTxt.Call("fadeovertime", 2f);
                    ReleaseTxt.Alpha = 0f;
                    AfterDelay(2000, () =>
                        {
                            ReleaseIcon.Call("destroy");
                            ReleaseTxt.Call("destroy");
                        });
                });

            for (int i = 0; i < 18; i++)
            {
                Entity player = Call<Entity>("getEntByNum", i);
                if (player != null && player.IsPlayer)
                    player.Call("playLocalSound", "RU_defeat_music");
            }            
        }

        private void ShowInfo(Entity ent)
        {
            ent.SetField("showingInfo", 1);
            if (ent.GetField<string>("sessionteam") != GetHiderTeam())
                goto Seeker;
            ent.Call("iPrintlnBold", "^4You are a Hider");

            ent.AfterDelay(2000, entity =>
                    {
                        entity.Call("iPrintlnBold", "^4Press [{+smoke}] to open model menu");
                        entity.AfterDelay(2000, player =>
                        {
                            player.Call("iPrintlnBold", "^4Hold [{+activate}] and [{+frag}] to spin model");
                            player.AfterDelay(2000, Ent =>
                            {
                                Ent.Call("iPrintlnBold", "^4Press [{+melee_zoom}] to change spin direction");
                                Ent.AfterDelay(2000, _Ent =>
                                {
                                    _Ent.Call("iPrintlnBold", "^4Press [{+actionslot 4}] to change model directly");
                                    _Ent.SetField("showingInfo", 0);
                                });
                            });
                        });
                    });
            return;

            Seeker:
            ent.Call("iPrintlnBold", "^4You are a Seeker");

            ent.AfterDelay(2000, entity =>
            {
                entity.Call("iPrintlnBold", "^4Search and kill the Hiders");
                entity.AfterDelay(2000, player =>
                {
                    player.Call("iPrintlnBold", "^4Press [{+actionslot 4}] to attach/detach silencer");
                    player.AfterDelay(2000, _Ent =>
                    {
                        _Ent.Call("iPrintlnBold", "^4The Hiders have taken the form of a map object");
                        _Ent.AfterDelay(2000, Ent =>
                        {
                            Ent.Call("iPrintlnBold", "^4Press [{+actionslot 6}] to enable/disable Seeker Sensor");
                            Ent.SetField("showingInfo", 0);
                        });
                    });
                });
            });
        }

        private void SetTeamNames()
        {
            string Hiders = GetHiderTeam();
            string Seekers = _Utility.GetOtherTeam(Hiders);
            Call("setdvar", "g_teamname_" + Hiders, "Hiders");
            Call("setdvar", "g_teamicon_" + Hiders, "iw5_cardicon_keegan");
            Call("setdvar", "g_teamicon_" + Seekers, "cardicon_hat_n_knife");
            Call("setdvar", "g_teamname_" + Seekers, "Seekers");
        }

        private string GetHiderTeam()
        {
            string HiderTeam = "axis";

            if (mapname == "mp_hardhat" || mapname == "mp_exchange")
                HiderTeam = _Utility.GetOtherTeam(HiderTeam);

            int RoundsPlayed = Call<int>("getteamscore", "allies");
            RoundsPlayed += Call<int>("getteamscore", "axis");
            int SideSwitches = (int)Math.Floor((float)RoundsPlayed/2);
            if (SideSwitches % 2 != 0)
            {
                HiderTeam = _Utility.GetOtherTeam(HiderTeam);
            }

            return HiderTeam;
        }

        private int GetTeamCount(string team)
        {
            int Count = 0;
            for (int i = 0; i < 18; i++)
            {
                Entity player = Call<Entity>("getEntByNum", i);
                if (player != null && player.IsPlayer)
                {
                    if (player.GetField<string>("sessionteam") == team)
                        Count++;
                }
            }
            return Count;
        }

        private int GetTimePassed()
        {
            int timePassed = Call<int>("gettime") - Call<int>("getstarttime");
            return timePassed;
        }

        private int GetTimeLeft()
        {
            float timelimit = float.Parse(Call<string>("getdvar", "scr_sd_timelimit")) * 60;
            int iTimelimit = (int)(timelimit * 1000);
            int timePassed = GetTimePassed();
            int timeLeft = iTimelimit - timePassed;

            return timeLeft;
        }
    }
}
