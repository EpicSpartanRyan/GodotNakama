
using Godot;
using Microsoft.Extensions.DependencyInjection;
using SampleGame.src.core;
using DiscordRPC;

namespace SampleGame.src.game;

public partial class NewScript : Node2D
{
	private int frame = 0;
    private DiscordRpcClient _discordClient;
	
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		
        _discordClient = DependencyContainer.Provider.GetRequiredService<DiscordRpcClient>();

        // Set the rich presence

        _discordClient.SetPresence(new RichPresence()
        {
           Details = "A Basic Example",
           State = "In Game",
           Assets = new Assets()
           {
               LargeImageKey = "godot",
               LargeImageText = "Godot Engine",
               SmallImageKey = "csharp",
               SmallImageText = ".NET version"
           } ,
           Buttons = new DiscordRPC.Button[]
           {
               new DiscordRPC.Button() { Label = "RPC Library Author", Url = "https://lachee.dev/"},
               new DiscordRPC.Button() { Label = "Multiplayer Template", Url = "https://github.com/EpicSpartanRyan/GodotNakama" }
           }
        });
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		frame += 1;
		// GD.Print("Current frame is: " + frame + " ; Current delta is: " + delta);
	}
}
