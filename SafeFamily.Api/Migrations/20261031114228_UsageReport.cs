using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SafeFamily.Api.Migrations
{
    /// <inheritdoc />
    public partial class UsageReport : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "UsageDays",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    DeviceId = table.Column<int>(type: "int", nullable: false),
                    Date = table.Column<DateOnly>(type: "date", nullable: false),
                    TotalMinutes = table.Column<int>(type: "int", nullable: false),
                    Blocks = table.Column<int>(type: "int", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UsageDays", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "UsageApps",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    UsageDayId = table.Column<int>(type: "int", nullable: false),
                    Package = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Minutes = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UsageApps", x => x.Id);
                    table.ForeignKey(
                        name: "FK_UsageApps_UsageDays_UsageDayId",
                        column: x => x.UsageDayId,
                        principalTable: "UsageDays",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_UsageApps_UsageDayId_Package",
                table: "UsageApps",
                columns: new[] { "UsageDayId", "Package" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_UsageDays_DeviceId_Date",
                table: "UsageDays",
                columns: new[] { "DeviceId", "Date" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "UsageApps");

            migrationBuilder.DropTable(
                name: "UsageDays");
        }
    }
}
