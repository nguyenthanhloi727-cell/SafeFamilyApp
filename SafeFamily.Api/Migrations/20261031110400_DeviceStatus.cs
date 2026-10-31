using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SafeFamily.Api.Migrations
{
    /// <inheritdoc />
    public partial class DeviceStatus : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "DeviceStatuses",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    DeviceId = table.Column<int>(type: "int", nullable: false),
                    BatteryPercent = table.Column<int>(type: "int", nullable: true),
                    PolicyVersion = table.Column<int>(type: "int", nullable: false),
                    IsPaused = table.Column<bool>(type: "bit", nullable: false),
                    StudyActive = table.Column<bool>(type: "bit", nullable: false),
                    PermissionsMissingJson = table.Column<string>(type: "nvarchar(max)", maxLength: 16384, nullable: false),
                    AppVersion = table.Column<string>(type: "nvarchar(32)", maxLength: 32, nullable: true),
                    TempUnlockedJson = table.Column<string>(type: "nvarchar(max)", maxLength: 16384, nullable: false),
                    ReportedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DeviceStatuses", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_DeviceStatuses_DeviceId",
                table: "DeviceStatuses",
                column: "DeviceId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DeviceStatuses");
        }
    }
}
