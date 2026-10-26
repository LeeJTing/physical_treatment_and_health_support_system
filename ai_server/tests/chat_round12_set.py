"""Round 12 of the continuous chatbot improvement (8 Oct, rules 3.17): practical questions about
specific exercises in the plans for balance / fall prevention, disuse atrophy, hip stability,
upper limb and the active circuit, the way older patients and carers ask them.
Written before looking at the rules; the first run is the honest score.
"""
BALANCE = "c84e6e5e-b43a-59fe-96ab-65e4b585e4f1"     # tandem stance, heel raise, sit to stand
DISUSE = "526ee6e0-0ca2-54d2-90bf-ad4476f08e2c"      # seated marching, sit to stand, shoulder abduction
HIP = "93ddd21e-2104-5363-a5ce-3f94904f52d3"         # hip abduction, tandem stance, glute bridge
UPPER = "45245b62-5696-56fe-9713-9af0b74f8768"       # elbow flexion, shoulder flexion, abduction, wall push-up
CIRCUIT = "2d9ac62b-2213-59d1-9eb9-dd228882c1aa"     # march in place, step up, mini squat, wall push-up

ROUND12 = [
    (BALANCE, "how long do i stand heel to toe", "exercise:tandem_stance"),
    (BALANCE, "i keep wobbling in tandem stance", ("weakness_balance", "exercise:tandem_stance")),
    (BALANCE, "can i hold the wall during the balance exercise", ("weakness_balance", "safety", "exercise:tandem_stance", "equipment", "fear_of_falling")),
    (BALANCE, "how high should my heels go", "exercise:heel_raise"),
    (BALANCE, "my calf tight after heel raise", ("pain_mild", "pain_or_discomfort", "exercise:heel_raise")),
    (DISUSE, "i have been in bed for 2 months, where do i start", ("getting_started", "weakness_balance", "muscle_loss")),
    (DISUSE, "my muscles very weak, can i do half the reps", ("difficulty", "weakness_balance")),
    (DISUSE, "can i use my hands to stand up first", ("difficulty", "exercise:sit_to_stand", "weakness_balance")),
    (DISUSE, "how do i do seated marching", "exercise:seated_marching"),
    (DISUSE, "which chair is best", "equipment"),
    (HIP, "which leg should i lift for hip abduction", "exercise:hip_abduction"),
    (HIP, "my hip clicks when i lift my leg sideways", ("joint_noise", "exercise:hip_abduction")),
    (HIP, "is the bridge good for back pain", ("exercise:glute_bridge", "plan_progress", "pain_or_discomfort")),
    (UPPER, "how close to the wall should i stand", "exercise:wall_push_up"),
    (UPPER, "can i use a water bottle as weight for elbow flexion", ("equipment", "exercise:elbow_flexion", "difficulty")),
    (UPPER, "both arms or one arm at a time", ("exercise:shoulder_abduction", "exercise:shoulder_flexion", "exercise:elbow_flexion", "how_to", "plan_exercises")),
    (UPPER, "my shoulder pain when arm above head", ("pain_or_discomfort", "pain_sharp")),
    (CIRCUIT, "how fast should i march", "exercise:march_in_place"),
    (CIRCUIT, "what is the order of my exercises", "plan_exercises"),
    (CIRCUIT, "do i rest between exercises", ("how_to", "how_often", "plan_exercises")),
    (CIRCUIT, "my step is 20cm too high?", "exercise:step_up"),
    (CIRCUIT, "my knees go past my toes in squat", ("exercise:mini_squat", "posture_result")),
    (BALANCE, "my grandma is scared to try standing on one line", ("for_someone_else", "weakness_balance", "safety", "exercise:tandem_stance")),
    (DISUSE, "how long before i can walk normally", "plan_progress"),
    (HIP, "glute bridge on bed or floor", ("exercise:glute_bridge", "equipment")),
    (UPPER, "what weight should i use", ("equipment", "difficulty")),
    (CIRCUIT, "i get out of breath marching", ("red_flag", "tired", "safety")),
    (BALANCE, "is it normal to feel unsteady", ("weakness_balance", "safety")),
    (DISUSE, "boleh buat senaman sambil duduk?", "difficulty"),
    (HIP, "berapa kali seminggu", "how_often"),
]
