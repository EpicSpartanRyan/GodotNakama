
using Godot;
using Microsoft.Extensions.DependencyInjection;
using Backtrace.Model;
using Backtrace;
using Game.Config;
using System;

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
          var credentials = new BacktraceCredentials(Secrets.BacktraceUrl);
          var client = new BacktraceClient(credentials);
          client.HandleApplicationException();
          return client;  
        });

        // We can add more services here in the future
        // services.AddTransient<NakamaClient>();

        _provider = services.BuildServiceProvider();
        GD.Print("Dependencies container initialized.");
    }
}