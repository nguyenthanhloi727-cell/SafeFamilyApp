using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Data;

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<Family> Families => Set<Family>();
    public DbSet<Parent> Parents => Set<Parent>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<Pairing> Pairings => Set<Pairing>();
    public DbSet<Policy> Policies => Set<Policy>();
    public DbSet<Command> Commands => Set<Command>();
    public DbSet<InstalledApp> InstalledApps => Set<InstalledApp>();
    public DbSet<LocationPoint> LocationPoints => Set<LocationPoint>();
    public DbSet<Geofence> Geofences => Set<Geofence>();
    public DbSet<GeofenceEvent> GeofenceEvents => Set<GeofenceEvent>();
    public DbSet<DeviceStatus> DeviceStatuses => Set<DeviceStatus>();
    public DbSet<ChildRequest> ChildRequests => Set<ChildRequest>();
    public DbSet<UsageDay> UsageDays => Set<UsageDay>();
    public DbSet<UsageApp> UsageApps => Set<UsageApp>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Parent>().HasIndex(p => p.Email).IsUnique();
        b.Entity<Parent>().Property(p => p.Email).HasMaxLength(256);
        b.Entity<RefreshToken>().HasIndex(t => t.TokenHash).IsUnique();
        b.Entity<RefreshToken>().Property(t => t.TokenHash).HasMaxLength(64);
        b.Entity<Pairing>().HasIndex(p => p.Code);
        b.Entity<Pairing>().Property(p => p.Code).HasMaxLength(6);
        b.Entity<Policy>().HasIndex(p => p.DeviceId).IsUnique();
        b.Entity<Command>().HasIndex(c => new { c.DeviceId, c.DoneAt });
        b.Entity<InstalledApp>().HasIndex(a => new { a.DeviceId, a.PackageName }).IsUnique();
        b.Entity<InstalledApp>().Property(a => a.PackageName).HasMaxLength(256);
        b.Entity<InstalledApp>().Property(a => a.Label).HasMaxLength(200);
        b.Entity<InstalledApp>().Property(a => a.Status).HasMaxLength(10).HasDefaultValue("allowed");
        b.Entity<LocationPoint>().HasIndex(l => new { l.DeviceId, l.Time });
        b.Entity<Geofence>().HasIndex(g => g.DeviceId);
        b.Entity<Geofence>().Property(g => g.Name).HasMaxLength(100);
        b.Entity<GeofenceEvent>().HasIndex(e => new { e.DeviceId, e.Time });
        b.Entity<GeofenceEvent>().Property(e => e.GeofenceName).HasMaxLength(100);
        b.Entity<GeofenceEvent>().Property(e => e.Type).HasMaxLength(10);
        b.Entity<DeviceStatus>().HasIndex(d => d.DeviceId).IsUnique();
        b.Entity<DeviceStatus>().Property(d => d.AppVersion).HasMaxLength(32);
        b.Entity<DeviceStatus>().Property(d => d.PermissionsMissingJson).HasMaxLength(StatusRules.MaxListJsonChars);
        b.Entity<DeviceStatus>().Property(d => d.TempUnlockedJson).HasMaxLength(StatusRules.MaxListJsonChars);
        b.Entity<ChildRequest>().HasIndex(r => new { r.DeviceId, r.Status });
        b.Entity<ChildRequest>().Property(r => r.Kind).HasMaxLength(20);
        b.Entity<ChildRequest>().Property(r => r.Status).HasMaxLength(10).IsConcurrencyToken(); // hai lần duyệt cùng lúc: chỉ một lần thắng
        b.Entity<ChildRequest>().Property(r => r.Payload).HasMaxLength(RequestRules.MaxPayloadBytes);
        b.Entity<UsageDay>().HasIndex(u => new { u.DeviceId, u.Date }).IsUnique(); // gửi lại cùng ngày thì ghi đè
        b.Entity<UsageDay>().HasMany(u => u.Apps).WithOne().HasForeignKey(a => a.UsageDayId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<UsageApp>().HasIndex(a => new { a.UsageDayId, a.Package }).IsUnique();
        b.Entity<UsageApp>().Property(a => a.Package).HasMaxLength(200);
    }
}
