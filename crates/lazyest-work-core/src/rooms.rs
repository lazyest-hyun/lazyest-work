use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimeRange {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

impl TimeRange {
    pub fn new(start: DateTime<Utc>, end: DateTime<Utc>) -> Self {
        Self { start, end }
    }

    pub fn duration(&self) -> Duration {
        self.end - self.start
    }

    pub fn overlaps(&self, other: &TimeRange) -> bool {
        self.start < other.end && other.start < self.end
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BusyBlock {
    pub calendar_id: String,
    pub range: TimeRange,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Room {
    pub id: String,
    pub email: String,
    pub name: String,
    pub building: Option<String>,
    pub floor: Option<String>,
    pub capacity: Option<u32>,
    #[serde(default)]
    pub features: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoomSearchRequest {
    pub desired: TimeRange,
    pub minimum_capacity: u32,
    #[serde(default)]
    pub required_features: Vec<String>,
    pub preferred_building: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoomSuggestion {
    pub room: Room,
    pub score: i32,
    pub reasons: Vec<String>,
}

pub fn suggest_rooms(
    rooms: &[Room],
    busy_blocks: &[BusyBlock],
    request: &RoomSearchRequest,
) -> Vec<RoomSuggestion> {
    let mut suggestions: Vec<RoomSuggestion> = rooms
        .iter()
        .filter(|room| room_satisfies_capacity(room, request.minimum_capacity))
        .filter(|room| room_has_features(room, &request.required_features))
        .filter(|room| room_is_free(room, busy_blocks, &request.desired))
        .map(|room| score_room(room, request))
        .collect();

    suggestions.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then_with(|| a.room.name.cmp(&b.room.name))
    });
    suggestions
}

fn room_satisfies_capacity(room: &Room, minimum_capacity: u32) -> bool {
    room.capacity.unwrap_or(0) >= minimum_capacity
}

fn room_has_features(room: &Room, required_features: &[String]) -> bool {
    required_features.iter().all(|required| {
        room.features
            .iter()
            .any(|feature| feature.eq_ignore_ascii_case(required))
    })
}

fn room_is_free(room: &Room, busy_blocks: &[BusyBlock], desired: &TimeRange) -> bool {
    busy_blocks
        .iter()
        .filter(|block| block.calendar_id == room.email || block.calendar_id == room.id)
        .all(|block| !block.range.overlaps(desired))
}

fn score_room(room: &Room, request: &RoomSearchRequest) -> RoomSuggestion {
    let mut score = 0;
    let mut reasons = Vec::new();

    if let Some(capacity) = room.capacity {
        let spare = capacity.saturating_sub(request.minimum_capacity);
        score += 100 - spare.min(40) as i32;
        reasons.push(format!("fits {capacity} people"));
    }

    if let (Some(preferred), Some(building)) = (&request.preferred_building, &room.building)
        && preferred.eq_ignore_ascii_case(building)
    {
        score += 30;
        reasons.push(format!("in {building}"));
    }

    for feature in &request.required_features {
        if room
            .features
            .iter()
            .any(|candidate| candidate.eq_ignore_ascii_case(feature))
        {
            score += 5;
        }
    }

    RoomSuggestion {
        room: room.clone(),
        score,
        reasons,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn dt(hour: u32, minute: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 5, 11, hour, minute, 0).unwrap()
    }

    fn room(name: &str, email: &str, capacity: u32, features: &[&str]) -> Room {
        Room {
            id: email.to_string(),
            email: email.to_string(),
            name: name.to_string(),
            building: Some("HQ".to_string()),
            floor: Some("7".to_string()),
            capacity: Some(capacity),
            features: features.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn filters_out_busy_rooms_and_sorts_best_fit_first() {
        let rooms = vec![
            room("Big Room", "big@example.com", 12, &["meet"]),
            room("Right Room", "right@example.com", 5, &["meet"]),
            room("Busy Room", "busy@example.com", 5, &["meet"]),
        ];
        let desired = TimeRange::new(dt(9, 0), dt(9, 30));
        let busy_blocks = vec![BusyBlock {
            calendar_id: "busy@example.com".to_string(),
            range: TimeRange::new(dt(9, 10), dt(9, 20)),
        }];
        let request = RoomSearchRequest {
            desired,
            minimum_capacity: 4,
            required_features: vec!["meet".to_string()],
            preferred_building: Some("HQ".to_string()),
        };

        let suggestions = suggest_rooms(&rooms, &busy_blocks, &request);

        assert_eq!(suggestions.len(), 2);
        assert_eq!(suggestions[0].room.name, "Right Room");
        assert_eq!(suggestions[1].room.name, "Big Room");
    }

    #[test]
    fn treats_touching_time_ranges_as_available() {
        let rooms = vec![room("Room", "room@example.com", 4, &[])];
        let desired = TimeRange::new(dt(10, 0), dt(10, 30));
        let busy_blocks = vec![BusyBlock {
            calendar_id: "room@example.com".to_string(),
            range: TimeRange::new(dt(9, 30), dt(10, 0)),
        }];
        let request = RoomSearchRequest {
            desired,
            minimum_capacity: 2,
            required_features: vec![],
            preferred_building: None,
        };

        assert_eq!(suggest_rooms(&rooms, &busy_blocks, &request).len(), 1);
    }
}
