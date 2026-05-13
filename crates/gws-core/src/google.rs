use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const CALENDAR_API_BASE: &str = "https://www.googleapis.com/calendar/v3";
pub const ADMIN_DIRECTORY_API_BASE: &str = "https://admin.googleapis.com/admin/directory/v1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FreeBusyItem {
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FreeBusyRequest {
    pub time_min: DateTime<Utc>,
    pub time_max: DateTime<Utc>,
    pub items: Vec<FreeBusyItem>,
}

impl FreeBusyRequest {
    pub fn for_calendars(
        time_min: DateTime<Utc>,
        time_max: DateTime<Utc>,
        calendar_ids: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        Self {
            time_min,
            time_max,
            items: calendar_ids
                .into_iter()
                .map(|id| FreeBusyItem { id: id.into() })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventDateTime {
    #[serde(rename = "dateTime")]
    pub date_time: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventAttendee {
    pub email: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resource: Option<bool>,
}

impl EventAttendee {
    pub fn person(email: impl Into<String>) -> Self {
        Self {
            email: email.into(),
            resource: None,
        }
    }

    pub fn room(email: impl Into<String>) -> Self {
        Self {
            email: email.into(),
            resource: Some(true),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InsertEventRequest {
    pub summary: String,
    pub start: EventDateTime,
    pub end: EventDateTime,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attendees: Vec<EventAttendee>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(rename = "conferenceData", skip_serializing_if = "Option::is_none")]
    pub conference_data: Option<Value>,
}

impl InsertEventRequest {
    pub fn new(summary: impl Into<String>, start: DateTime<Utc>, end: DateTime<Utc>) -> Self {
        Self {
            summary: summary.into(),
            start: EventDateTime { date_time: start },
            end: EventDateTime { date_time: end },
            attendees: Vec::new(),
            location: None,
            description: None,
            conference_data: None,
        }
    }

    pub fn with_room(mut self, room_email: impl Into<String>) -> Self {
        self.attendees.push(EventAttendee::room(room_email));
        self
    }

    pub fn with_person(mut self, email: impl Into<String>) -> Self {
        self.attendees.push(EventAttendee::person(email));
        self
    }

    pub fn with_meet(mut self, request_id: impl Into<String>) -> Self {
        self.conference_data = Some(json!({
            "createRequest": {
                "requestId": request_id.into(),
                "conferenceSolutionKey": { "type": "hangoutsMeet" }
            }
        }));
        self
    }
}

pub fn freebusy_url() -> &'static str {
    "https://www.googleapis.com/calendar/v3/freeBusy"
}

pub fn events_insert_url(calendar_id: &str) -> String {
    format!(
        "{CALENDAR_API_BASE}/calendars/{}/events",
        url_path_encode(calendar_id)
    )
}

pub fn calendar_resources_url(customer: &str) -> String {
    format!(
        "{ADMIN_DIRECTORY_API_BASE}/customer/{}/resources/calendars",
        url_path_encode(customer)
    )
}

fn url_path_encode(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(byte as char);
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn serializes_room_attendee_as_resource() {
        let start = Utc.with_ymd_and_hms(2026, 5, 11, 9, 0, 0).unwrap();
        let end = Utc.with_ymd_and_hms(2026, 5, 11, 9, 30, 0).unwrap();
        let req = InsertEventRequest::new("Planning", start, end)
            .with_person("alice@example.com")
            .with_room("room@example.com");

        let value = serde_json::to_value(req).unwrap();

        assert_eq!(value["attendees"][0]["email"], "alice@example.com");
        assert!(value["attendees"][0].get("resource").is_none());
        assert_eq!(value["attendees"][1]["resource"], true);
    }

    #[test]
    fn encodes_calendar_ids_in_paths() {
        assert_eq!(
            events_insert_url("room a@example.com"),
            "https://www.googleapis.com/calendar/v3/calendars/room%20a%40example.com/events"
        );
    }
}
