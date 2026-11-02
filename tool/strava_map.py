"""Ćwiczenia Formy → exercise_type Stravy (JSON upload serii, docs/uploads „Supported Exercises”)."""

STRAVA = {
    "jumping_jacks": "JUMPING_JACKS", "step_jacks": "JUMPING_JACKS", "march": "STANDING_MARCH",
    "high_knees": "HIGH_KNEES", "butt_kicks": "CARDIO_GENERIC", "arm_circles": "ARM_CIRCLES",
    "shadow_boxing": "CARDIO_GENERIC", "mountain_climbers": "MOUNTAIN_CLIMBER", "burpees": "BURPEE",
    "squat_thrust": "SQUAT_THRUSTS", "jump_squats": "BODY_WEIGHT_JUMP_SQUAT", "skaters": "LATERAL_LEAP_AND_HOP",
    "inchworm": "WALKOUT", "squat": "AIR_SQUAT", "sumo_squat": "SUMO_SQUAT", "reverse_lunge": "REVERSE_LUNGE",
    "side_lunge": "SIDE_LUNGE", "glute_bridge": "GLUTE_BRIDGE", "single_leg_bridge": "SINGLE_LEG_GLUTE_BRIDGE",
    "wall_sit": "WALL_SIT", "calf_raises": "STANDING_CALF_RAISE", "donkey_kicks": "DONKEY_KICKS",
    "good_morning": "SINGLE_LEG_BODYWEIGHT_ROMANIAN_DEADLIFTS", "step_ups": "STEP_UP", "split_squat": "STATIC_LUNGE",
    "side_leg_raise": "SIDE_LYING_LEG_RAISE", "pushups": "PUSH_UP_GENERIC", "knee_pushups": "MODIFIED_PUSH_UP",
    "incline_pushups": "INCLINE_PUSH_UP", "pike_pushups": "PIKE_PUSH_UP", "triceps_dips": "CHAIR_DIPS",
    "shoulder_taps": "PLANK_SHOULDER_TAP", "superman": "SUPERMAN_FROM_FLOOR", "plank": "PLANK_GENERIC",
    "side_plank": "SIDE_PLANK", "crunches": "CRUNCH", "bicycle": "BICYCLE_CRUNCH", "leg_raises": "LYING_STRAIGHT_LEG_RAISE",
    "flutter_kicks": "FLUTTER_KICKS", "dead_bug": "DEADBUG", "hollow_hold": "HOLLOW_ROCK", "russian_twist": "RUSSIAN_TWIST",
    "bird_dog": "BIRD_DOG", "cat_cow": "CAT_COW", "childs_pose": "CHILDS_POSE_LAT_STRETCH", "cobra": "COBRA",
    "down_dog": "STRETCH", "hamstring_stretch": "STANDING_HAMSTRING_STRETCH", "quad_stretch": "STANDING_QUAD_STRETCH",
    "hip_flexor_stretch": "KNEELING_HIP_FLEXOR_STRETCH", "knee_hug": "WALKING_KNEE_HUGS", "side_bend": "SIDE_BEND",
    "deep_squat_hold": "STRETCH", "goblet_squat": "GOBLET_SQUAT", "db_row": "BENT_OVER_DUMBBELL_ROW",
    "db_press": "OVERHEAD_DUMBBELL_PRESS", "db_curl": "STANDING_DUMBBELL_BICEPS_CURL", "db_lateral": "LATERAL_RAISE_GENERIC",
    "db_rdl": "DUMBBELL_ROMANIAN_DEADLIFTS", "kb_swing": "OLYMPIC_LIFT_GENERIC", "band_pull_apart": "BAND_PULLAPARTS",
    "band_row": "ROW_GENERIC", "pullups": "PULL_UP_GENERIC", "hanging_knee_raise": "HANGING_KNEE_RAISE",
    "forward_lunge": "LUNGE_GENERIC", "jump_lunge": "ALTERNATING_JUMP_LUNGE", "curtsy_lunge": "CURTSY_LUNGE",
    "squat_pulse": "AIR_SQUAT", "prisoner_squat": "AIR_SQUAT", "cossack_squat": "COSSACK_SQUAT",
    "sl_rdl": "SINGLE_LEG_BODYWEIGHT_ROMANIAN_DEADLIFTS", "sl_calf_raise": "SINGLE_LEG_STANDING_CALF_RAISE",
    "pistol_squat": "PISTOL_SQUAT", "box_squat": "SQUAT_GENERIC", "hip_thrust": "HIP_THRUST",
    "band_walk": "LATERAL_WALKS_WITH_BAND_AT_ANKLES", "band_bridge": "GLUTE_BRIDGE", "bridge_hold": "GLUTE_BRIDGE",
    "db_lunge": "DUMBBELL_REVERSE_LUNGE", "db_sumo": "DUMBBELL_SQUAT", "db_step_up": "STEP_UP",
    "kb_deadlift": "KETTLEBELL_DEADLIFT", "db_calf_raise": "SINGLE_LEG_DUMBBELL_STANDING_CALF_RAISE",
    "reverse_angels": "SHOULDER_STABILITY_GENERIC", "prone_w": "FLOOR_T_RAISE", "prone_y": "FLOOR_Y_RAISE",
    "superman_pull": "SUPERMAN", "swimmers": "SWIMMING", "door_row": "INVERTED_ROW", "tabletop": "HIP_RAISE",
    "reverse_plank": "REVERSE_PLANK", "scap_squeeze": "SCAPULAR_RETRACTION", "plank_up_down": "PLANK_TO_PUSH_UP",
    "plank_to_dog": "PLANK_GENERIC", "bear_crawl": "BEAR_CRAWL", "small_arm_circles": "ARM_CIRCLES",
    "wall_angels": "WALL_SLIDE", "floor_dips": "FLOOR_TRICEPS_DIP", "diamond_pushups": "DIAMOND_PUSH_UP",
    "wide_pushups": "PUSH_UP_GENERIC", "decline_pushups": "DECLINE_PUSH_UP", "high_plank": "PLANK_HOLD",
    "kpush_narrow": "MODIFIED_PUSH_UP", "punch_up": "CARDIO_GENERIC", "inverted_row": "INVERTED_ROW",
    "chin_ups": "CLOSE_GRIP_CHIN_UP", "dead_hang": "DEAD_HANG", "scap_pulls": "PULL_UP_GENERIC",
    "negative_pullups": "NEGATIVE_PULL_UP", "hanging_leg_raise": "HANGING_LEG_RAISE",
    "db_one_arm_row": "DUMBBELL_ROW", "db_reverse_fly": "DUMBBELL_REAR_DELT_FLY", "db_shrug": "DUMBBELL_SHRUG",
    "renegade_row": "RENEGADE_ROW", "db_pullover": "DUMBBELL_PULLOVER", "db_hammer_curl": "DUMBBELL_HAMMER_CURL",
    "db_triceps_ext": "OVERHEAD_DUMBBELL_TRICEPS_EXTENSION", "db_kickback": "DUMBBELL_KICKBACK",
    "db_skull_crusher": "DUMBBELL_SKULLCRUSHER", "db_floor_press": "DUMBBELL_FLOOR_PRESS", "db_front_raise": "FRONT_RAISE",
    "db_arnold": "ARNOLD_PRESS", "db_thruster": "DUMBBELL_THRUSTERS", "kb_press": "STANDING_SINGLE_ARM_SHOULDER_PRESS",
    "band_chest_press": "CHEST_PRESS", "band_curl": "CURL_GENERIC", "band_press": "SHOULDER_PRESS_GENERIC",
    "band_pushdown": "TRICEPS_PRESSDOWN", "band_pulldown": "LAT_PULLDOWN", "band_face_pull": "FACE_PULL",
    "band_dislocates": "RESISTANCE_BAND_GENERIC", "v_ups": "V_UP", "reverse_crunch": "REVERSE_CRUNCH",
    "toe_touches": "DIAGONAL_TOE_TAP", "sit_ups": "SIT_UP_GENERIC", "seated_tucks": "LYING_KNEE_RAISE",
    "side_plank_dips": "SIDE_PLANK", "knee_to_elbow": "ELBOW_TO_KNEE", "kb_russian_twist": "DUMBBELL_RUSSIAN_TWIST",
    "jog_in_place": "RUNNING", "star_jumps": "FULL_STAR_JUMPS", "tuck_jumps": "PLYO_GENERIC", "jump_rope": "JUMP_ROPE",
    "lateral_shuffle": "AGILITY_LADDER", "worlds_greatest": "WORLDS_GREATEST_STRETCH", "hip_circles": "STANDING_HIP_CIRCLES",
    "leg_swings": "FORWARD_AND_BACKWARD_LEG_SWINGS", "thoracic_open": "THORACIC_ROTATION", "butterfly": "STRETCH",
    "calf_stretch": "TOES_AGAINST_WALL_CALF_STRETCH", "chest_stretch": "WALL_CHEST_STRETCH",
    "triceps_stretch": "OVERHEAD_TRICEP_STRETCH", "shoulder_stretch": "CROSS_BODY_SHOULDER_STRETCH",
    "standing_fold": "STANDING_HAMSTRING_STRETCH", "sphinx": "COBRA", "figure_four": "LYING_PIRIFORMIS_STRETCH",
    "breathing": "STRETCH", "bridge_march": "GLUTE_BRIDGE", "punch_squat": "AIR_SQUAT", "squat_reach": "AIR_SQUAT",
    "squat_knee": "STEP_UP_AND_KNEE_DRIVE", "toe_touch_squat": "AIR_SQUAT", "chair_pose": "WALL_SIT",
    "lateral_jump_squat": "LATERAL_LEAP_AND_HOP", "frog_jumps": "BROAD_JUMP", "chair_pistol": "ASSISTED_PISTOL_SQUATS",
    "atg_split_squat": "STATIC_LUNGE", "lunge_knee_drive": "REVERSE_LUNGE", "leg_curl_standing": "WARM_UP_GENERIC",
    "donkey_straight": "GLUTE_KICKBACK_ON_FLOOR", "fire_hydrant": "FIRE_HYDRANTS", "inner_thigh_raise": "STANDING_ADDUCTION",
    "side_leg_standing": "STANDING_HIP_ABDUCTION", "supine_march": "LYING_KNEE_RAISE", "alt_leg_raise": "STRAIGHT_LEG_RAISE",
    "leg_circles": "FIGURE_OF_8S", "crunch_legs_up": "CRUNCH", "side_crunch": "OBLIQUE_CRUNCH", "heel_taps": "HEEL_TAPS",
    "roll_up": "ROLL_DOWN", "rolling_ball": "CORE_GENERIC", "hundred": "THE_HUNDRED", "teaser": "THE_TEASER",
    "v_sit_hold": "V_UP", "torso_twist": "WARM_UP_GENERIC", "lumbar_rotation": "LYING_SPINAL_TWIST",
    "plank_reach": "PLANK_WITH_ARM_RAISE", "two_point_plank": "PLANK_WITH_ARM_RAISE", "plank_jacks": "CARDIO_CORE_CRAWL",
    "plank_jump_in": "SQUAT_THRUSTS", "plank_leg_raise": "PLANK_GENERIC", "scap_pushup": "PUSH_UP_GENERIC",
    "reverse_plank_kick": "REVERSE_PLANK", "crab_walk": "CORE_GENERIC", "side_plank_knee": "SIDE_PLANK",
    "side_plank_leg": "SIDE_PLANK_LEG_RAISE", "ab_rollout": "AB_WHEEL_ROLLOUT", "prone_t": "FLOOR_T_RAISE",
    "wall_pushup": "WALL_PUSH_UP", "hindu_pushup": "PUSH_UP_GENERIC", "swim_strokes": "SWIMMING",
    "pallof_press": "PALLOF_PRESS", "clap_pushup": "CLAP_PUSH_UPS", "spiderman_pushup": "PUSH_UP_GENERIC",
    "pushup_tap": "PRESS_UP_POSITION_SHOULDER_TAP", "t_pushup": "PUSH_UP_GENERIC", "handstand_pushup": "HANDSTAND_PUSH_UP",
    "cross_climber": "CROSS_BODY_MOUNTAIN_CLIMBER", "step_touch": "WARM_UP_GENERIC", "front_kicks": "WALKING_HIGH_KICKS",
    "single_leg_hops": "POGO_JUMPS", "side_hops": "LATERAL_LEAP_AND_HOP", "side_reach": "WARM_UP_GENERIC",
    "pushup_burpee": "BURPEE", "pigeon": "PIGEON_POSE", "thread_needle": "THREAD_THE_NEEDLE_STRETCH",
    "lying_hamstring": "LYING_HAMSTRING_STRETCH", "wide_fold": "SEATED_HAMSTRING_STRETCH", "knee_circles": "WARM_UP_GENERIC",
    "shoulder_rolls": "SHOULDER_ROTATIONS", "neck_tilts": "NECK_TILTS", "warrior2": "STRETCH", "triangle": "STRETCH",
    "windmill": "WARM_UP_GENERIC", "standing_backbend": "STRETCH", "upper_back_stretch": "STRETCH",
    "wrist_mobility": "WARM_UP_GENERIC", "ankle_circles": "ANKLE_CIRCLES", "plow": "STRETCH", "shoulder_stand": "STRETCH",
    "fish_pose": "STRETCH", "mountain_pose": "STRETCH",
}

# identyfikatory potwierdzone na liście Stravy (literówka = odrzucony plik)
VALID = set("""
JUMPING_JACKS STANDING_MARCH HIGH_KNEES CARDIO_GENERIC ARM_CIRCLES MOUNTAIN_CLIMBER BURPEE SQUAT_THRUSTS
BODY_WEIGHT_JUMP_SQUAT LATERAL_LEAP_AND_HOP WALKOUT AIR_SQUAT SUMO_SQUAT REVERSE_LUNGE SIDE_LUNGE GLUTE_BRIDGE
SINGLE_LEG_GLUTE_BRIDGE WALL_SIT STANDING_CALF_RAISE DONKEY_KICKS SINGLE_LEG_BODYWEIGHT_ROMANIAN_DEADLIFTS STEP_UP
STATIC_LUNGE SIDE_LYING_LEG_RAISE PUSH_UP_GENERIC MODIFIED_PUSH_UP INCLINE_PUSH_UP PIKE_PUSH_UP CHAIR_DIPS
PLANK_SHOULDER_TAP SUPERMAN_FROM_FLOOR PLANK_GENERIC SIDE_PLANK CRUNCH BICYCLE_CRUNCH LYING_STRAIGHT_LEG_RAISE
FLUTTER_KICKS DEADBUG HOLLOW_ROCK RUSSIAN_TWIST BIRD_DOG CAT_COW CHILDS_POSE_LAT_STRETCH COBRA STRETCH
STANDING_HAMSTRING_STRETCH STANDING_QUAD_STRETCH KNEELING_HIP_FLEXOR_STRETCH WALKING_KNEE_HUGS SIDE_BEND GOBLET_SQUAT
BENT_OVER_DUMBBELL_ROW OVERHEAD_DUMBBELL_PRESS STANDING_DUMBBELL_BICEPS_CURL LATERAL_RAISE_GENERIC
DUMBBELL_ROMANIAN_DEADLIFTS OLYMPIC_LIFT_GENERIC BAND_PULLAPARTS ROW_GENERIC PULL_UP_GENERIC HANGING_KNEE_RAISE
LUNGE_GENERIC ALTERNATING_JUMP_LUNGE CURTSY_LUNGE COSSACK_SQUAT SINGLE_LEG_STANDING_CALF_RAISE PISTOL_SQUAT
SQUAT_GENERIC HIP_THRUST LATERAL_WALKS_WITH_BAND_AT_ANKLES DUMBBELL_REVERSE_LUNGE DUMBBELL_SQUAT KETTLEBELL_DEADLIFT
SINGLE_LEG_DUMBBELL_STANDING_CALF_RAISE SHOULDER_STABILITY_GENERIC FLOOR_T_RAISE FLOOR_Y_RAISE SUPERMAN SWIMMING
INVERTED_ROW HIP_RAISE REVERSE_PLANK SCAPULAR_RETRACTION PLANK_TO_PUSH_UP BEAR_CRAWL WALL_SLIDE FLOOR_TRICEPS_DIP
DIAMOND_PUSH_UP DECLINE_PUSH_UP PLANK_HOLD CLOSE_GRIP_CHIN_UP DEAD_HANG NEGATIVE_PULL_UP HANGING_LEG_RAISE
DUMBBELL_ROW DUMBBELL_REAR_DELT_FLY DUMBBELL_SHRUG RENEGADE_ROW DUMBBELL_PULLOVER DUMBBELL_HAMMER_CURL
OVERHEAD_DUMBBELL_TRICEPS_EXTENSION DUMBBELL_KICKBACK DUMBBELL_SKULLCRUSHER DUMBBELL_FLOOR_PRESS FRONT_RAISE
ARNOLD_PRESS DUMBBELL_THRUSTERS STANDING_SINGLE_ARM_SHOULDER_PRESS CHEST_PRESS CURL_GENERIC SHOULDER_PRESS_GENERIC
TRICEPS_PRESSDOWN LAT_PULLDOWN FACE_PULL RESISTANCE_BAND_GENERIC V_UP REVERSE_CRUNCH DIAGONAL_TOE_TAP SIT_UP_GENERIC
LYING_KNEE_RAISE ELBOW_TO_KNEE DUMBBELL_RUSSIAN_TWIST RUNNING FULL_STAR_JUMPS PLYO_GENERIC JUMP_ROPE AGILITY_LADDER
WORLDS_GREATEST_STRETCH STANDING_HIP_CIRCLES FORWARD_AND_BACKWARD_LEG_SWINGS THORACIC_ROTATION
TOES_AGAINST_WALL_CALF_STRETCH WALL_CHEST_STRETCH OVERHEAD_TRICEP_STRETCH CROSS_BODY_SHOULDER_STRETCH
LYING_PIRIFORMIS_STRETCH STEP_UP_AND_KNEE_DRIVE BROAD_JUMP ASSISTED_PISTOL_SQUATS WARM_UP_GENERIC
GLUTE_KICKBACK_ON_FLOOR FIRE_HYDRANTS STANDING_ADDUCTION STANDING_HIP_ABDUCTION STRAIGHT_LEG_RAISE FIGURE_OF_8S
OBLIQUE_CRUNCH HEEL_TAPS ROLL_DOWN CORE_GENERIC THE_HUNDRED THE_TEASER LYING_SPINAL_TWIST PLANK_WITH_ARM_RAISE
CARDIO_CORE_CRAWL SIDE_PLANK_LEG_RAISE AB_WHEEL_ROLLOUT WALL_PUSH_UP PALLOF_PRESS CLAP_PUSH_UPS
PRESS_UP_POSITION_SHOULDER_TAP HANDSTAND_PUSH_UP CROSS_BODY_MOUNTAIN_CLIMBER WALKING_HIGH_KICKS POGO_JUMPS
PIGEON_POSE THREAD_THE_NEEDLE_STRETCH LYING_HAMSTRING_STRETCH SEATED_HAMSTRING_STRETCH SHOULDER_ROTATIONS NECK_TILTS
ANKLE_CIRCLES TOTAL_BODY_GENERIC
""".split())

FALLBACK = {"cardio": "CARDIO_GENERIC", "core": "CORE_GENERIC", "warmup": "WARM_UP_GENERIC",
            "mobility": "WARM_UP_GENERIC", "stretch": "STRETCH", "strength": "TOTAL_BODY_GENERIC"}
