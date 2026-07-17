use anyhow::Context;
use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand};
use lazyest_work_core::google::{
    FreeBusyRequest, InsertEventRequest, calendar_resources_url, events_insert_url, freebusy_url,
};

#[derive(Debug, Parser)]
#[command(name = "lazyest-work-cli")]
#[command(about = "Development helper for Lazyest Work's Rust core")]
struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    FreebusyJson {
        #[arg(long)]
        start: String,
        #[arg(long)]
        end: String,
        #[arg(long = "calendar")]
        calendars: Vec<String>,
    },
    InsertEventJson {
        #[arg(long)]
        summary: String,
        #[arg(long)]
        start: String,
        #[arg(long)]
        end: String,
        #[arg(long = "room")]
        rooms: Vec<String>,
        #[arg(long = "attendee")]
        attendees: Vec<String>,
    },
    Endpoints {
        #[arg(long, default_value = "primary")]
        calendar: String,
        #[arg(long, default_value = "my_customer")]
        customer: String,
    },
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    match args.command {
        Command::FreebusyJson {
            start,
            end,
            calendars,
        } => {
            let request =
                FreeBusyRequest::for_calendars(parse_time(&start)?, parse_time(&end)?, calendars);
            println!("{}", serde_json::to_string_pretty(&request)?);
        }
        Command::InsertEventJson {
            summary,
            start,
            end,
            rooms,
            attendees,
        } => {
            let mut request =
                InsertEventRequest::new(summary, parse_time(&start)?, parse_time(&end)?);
            for attendee in attendees {
                request = request.with_person(attendee);
            }
            for room in rooms {
                request = request.with_room(room);
            }
            println!("{}", serde_json::to_string_pretty(&request)?);
        }
        Command::Endpoints { calendar, customer } => {
            let payload = serde_json::json!({
                "freebusy": freebusy_url(),
                "eventsInsert": events_insert_url(&calendar),
                "calendarResources": calendar_resources_url(&customer),
            });
            println!("{}", serde_json::to_string_pretty(&payload)?);
        }
    }
    Ok(())
}

fn parse_time(value: &str) -> anyhow::Result<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .with_context(|| format!("expected RFC3339 timestamp, got {value}"))
        .map(|dt| dt.with_timezone(&Utc))
}
