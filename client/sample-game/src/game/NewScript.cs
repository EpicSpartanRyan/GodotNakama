using Godot;
using System;
using Backtrace.Model;
using Backtrace;
using Microsoft.Extensions.DependencyInjection;
using SampleGame.src.core;
using DiscordRPC;

namespace SampleGame.src.game;

public partial class NewScript : Node2D
{
	private int frame = 0;
	private BacktraceClient _backtraceClient;
    private DiscordRpcClient _discordClient;
	
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		
		_backtraceClient = DependencyContainer.Provider.GetRequiredService<BacktraceClient>();
        _discordClient = DependencyContainer.Provider.GetRequiredService<DiscordRpcClient>();

        // Set the rich presence

        _discordClient.SetPresence(new RichPresence()
        {
           Details = "A Basic Example",
           State = "In Game",
           Assets = new Assets()
           {
               LargeImageKey = "godot",
               LargeImageText = "Lachee's Discord IPC Library",
               SmallImageKey = "godot"
           } ,
           Buttons = new DiscordRPC.Button[]
           {
               new DiscordRPC.Button() { Label = "lachee.dev", Url = "https://lachee.dev/"},
               new DiscordRPC.Button() { Label = "Multiplayer Template", Url = "https://github.com/EpicSpartanRyan/GodotNakama" }
           }
        });

		try
		{
			throw new InvalidOperationException("Excepción de prueba para verificar la integración de Backtrace en Godot 4.");
		}
		catch (InvalidOperationException exception)
		{
			var report = new BacktraceReport(exception);
			
			var versionInfo = Engine.GetVersionInfo();
			string engineVersion = versionInfo.ContainsKey("string") ? versionInfo["string"].ToString() : "Unknown";
			report.Attributes.Add("godot.version", engineVersion);
			
			_backtraceClient.Send(report);
			GD.PrintErr("Excepción de prueba enviada a Backtrace exitosamente.");
		}
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		frame += 1;
		// GD.Print("Current frame is: " + frame + " ; Current delta is: " + delta);
	}
}
