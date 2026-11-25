#ifndef ZIGSDL3DEMO_JOLT_BRIDGE_H
#define ZIGSDL3DEMO_JOLT_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PhysicsWorld PhysicsWorld;

enum { PHYSICS_STATIC = 0, PHYSICS_DYNAMIC = 1 };
enum { PHYSICS_BOX, PHYSICS_SPHERE, PHYSICS_CAPSULE, PHYSICS_MESH };

typedef struct PhysicsVec3 { float x, y, z; } PhysicsVec3;
typedef struct PhysicsPose {
    PhysicsVec3 position;
    float rotation[4]; /* x, y, z, w */
} PhysicsPose;

typedef struct PhysicsBodyDesc {
    PhysicsPose pose;
    PhysicsVec3 velocity;
    PhysicsVec3 angular_velocity;
    uint64_t user_data;
    uint32_t layer;
    uint32_t shape;
    PhysicsVec3 size;
    const PhysicsVec3 *vertices;
    const uint32_t *indices;
    size_t vertex_count, index_count;
} PhysicsBodyDesc;

typedef struct PhysicsBodyState {
    PhysicsPose pose;
    PhysicsVec3 velocity;
    PhysicsVec3 angular_velocity;
    bool active;
} PhysicsBodyState;

typedef struct PhysicsRayHit {
    uint64_t user_data;
    PhysicsVec3 position;
    PhysicsVec3 normal;
    float fraction;
} PhysicsRayHit;

typedef struct PhysicsCharacterState {
    PhysicsVec3 feet;
    bool grounded;
} PhysicsCharacterState;

PhysicsWorld *physics_world_create(void);
void physics_world_destroy(PhysicsWorld *world);
uint32_t physics_world_step(PhysicsWorld *world, float dt);
bool physics_body_create(PhysicsWorld *world, const PhysicsBodyDesc *desc, uint32_t *id);
void physics_body_destroy(PhysicsWorld *world, uint32_t id);
void physics_body_state(const PhysicsWorld *world, uint32_t id, PhysicsBodyState *state);
bool physics_raycast(const PhysicsWorld *world, PhysicsVec3 origin, PhysicsVec3 displacement,
                     uint32_t layer_mask, PhysicsRayHit *hit);
bool physics_character_create(PhysicsWorld *world, PhysicsVec3 feet, float radius, float half_height);
void physics_character_step(PhysicsWorld *world, float dt, float vx, float vz, bool jump);
PhysicsCharacterState physics_character_state(const PhysicsWorld *world);

#ifdef __cplusplus
}
#endif

#endif
