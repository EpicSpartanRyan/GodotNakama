
using Godot;
using Microsoft.Extensions.DependencyInjection;
using Backtrace.Model;
using Backtrace;
using SampleGame.src.config;
using System;
using DiscordRPC;

namespace SampleGame.src.core;

public partial class DependencyContainer : Node
{
	private static IServiceProvider _provider;

	// Property that guarantees container existence before returning it
	public static IServiceProvider Provider
	{
		get
		{
			if (_provider == null)
			{
				BuildContainer();
			}
			return _provider;
		}
	}

	public static void BuildContainer()
	{
		var services = new ServiceCollection();

		// Register Backtrace as Singleton
		services.AddSingleton<BacktraceClient>(sp =>
		{
            var credentials = new BacktraceCredentials(SampleGame.src.config.Secrets.BacktraceUrl);
            var client = new BacktraceClient(credentials);
            client.HandleApplicationException();
            return client;  
		});

		// We can add more services here in the future
		// services.AddTransient<NakamaClient>();

        services.AddSingleton<DiscordRpcClient>(sp =>
        {
            var client =new DiscordRpcClient(SampleGame.src.config.Secrets.DiscordAppId);
            {
                var logger = new DiscordRPC.Logging.ConsoleLogger(DiscordRPC.Logging.LogLevel.Info, true);
            }

            client.OnReady += (sender, e) =>
            {
                GD.Print($"Connected to discord with user {e.User.Username}");
                GD.Print($"Avatar: {e.User.GetAvatarURL(User.AvatarFormat.WebP)}");
            };

            client.Initialize();
            return client;
        });

		_provider = services.BuildServiceProvider();
		GD.Print("Dependencies container initialized.");
	}
}
