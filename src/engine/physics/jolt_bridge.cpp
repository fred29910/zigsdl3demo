#include <Jolt/Jolt.h>

#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceTable.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterTable.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterTable.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/PhysicsSystem.h>

#include <algorithm>
#include <mutex>
#include <new>

#include "jolt_bridge.h"

namespace {
using namespace JPH;

constexpr uint layer_count = 2;
std::mutex runtime_mutex;
size_t world_count = 0;

void acquireRuntime()
{
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (world_count == 0) {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
    }
    ++world_count;
}

void releaseRuntime()
{
    std::lock_guard<std::mutex> guard(runtime_mutex);
    if (--world_count == 0) {
        UnregisterTypes();
        delete Factory::sInstance;
        Factory::sInstance = nullptr;
    }
}

Vec3 vec(PhysicsVec3 value)
{
    return Vec3(value.x, value.y, value.z);
}

PhysicsVec3 pack(Vec3Arg value)
{
    return {value.GetX(), value.GetY(), value.GetZ()};
}

ShapeSettings::ShapeResult createShape(const PhysicsBodyDesc &desc)
{
    switch (desc.shape) {
    case PHYSICS_BOX: {
        const float convex_radius = std::min(0.05f, 0.1f * std::min({desc.size.x, desc.size.y, desc.size.z}));
        return BoxShapeSettings(vec(desc.size), convex_radius).Create();
    }
    case PHYSICS_SPHERE:
        return SphereShapeSettings(desc.size.x).Create();
    case PHYSICS_CAPSULE:
        return CapsuleShapeSettings(desc.size.y, desc.size.x).Create();
    case PHYSICS_MESH: {
        VertexList vertices;
        vertices.reserve(desc.vertex_count);
        for (size_t i = 0; i < desc.vertex_count; ++i) {
            const PhysicsVec3 &p = desc.vertices[i];
            vertices.emplace_back(p.x, p.y, p.z);
        }
        IndexedTriangleList triangles;
        triangles.reserve(desc.index_count / 3);
        for (size_t i = 0; i < desc.index_count; i += 3)
            triangles.emplace_back(desc.indices[i], desc.indices[i + 1], desc.indices[i + 2], 0);
        return MeshShapeSettings(std::move(vertices), std::move(triangles)).Create();
    }
    default:
        return {};
    }
}

class RayLayerFilter final : public ObjectLayerFilter {
public:
    explicit RayLayerFilter(uint32_t mask) : mask(mask) {}
    bool ShouldCollide(ObjectLayer layer) const override
    {
        return (mask & (1u << layer)) != 0;
    }

private:
    uint32_t mask;
};
} // namespace

struct PhysicsWorld {
    JPH::BroadPhaseLayerInterfaceTable broadphase{layer_count, layer_count};
    JPH::ObjectLayerPairFilterTable pairs{layer_count};
    JPH::ObjectVsBroadPhaseLayerFilterTable object_vs_broadphase;
    JPH::TempAllocatorImplWithMallocFallback temp{8 * 1024 * 1024};
    JPH::JobSystemSingleThreaded jobs{JPH::cMaxPhysicsJobs};
    JPH::PhysicsSystem system;
    JPH::Ref<JPH::CharacterVirtual> character;

    PhysicsWorld() : object_vs_broadphase(configureBroadphase(), layer_count, pairs, layer_count)
    {
        system.Init(4096, 0, 8192, 4096, broadphase, object_vs_broadphase, pairs);
    }

private:
    // Jolt precomputes the object/broadphase filter during construction.
    const JPH::BroadPhaseLayerInterfaceTable &configureBroadphase()
    {
        broadphase.MapObjectToBroadPhaseLayer(PHYSICS_STATIC, JPH::BroadPhaseLayer(PHYSICS_STATIC));
        broadphase.MapObjectToBroadPhaseLayer(PHYSICS_DYNAMIC, JPH::BroadPhaseLayer(PHYSICS_DYNAMIC));
        pairs.EnableCollision(PHYSICS_STATIC, PHYSICS_DYNAMIC);
        pairs.EnableCollision(PHYSICS_DYNAMIC, PHYSICS_DYNAMIC);
        return broadphase;
    }
};

extern "C" PhysicsWorld *physics_world_create()
{
    acquireRuntime();
    PhysicsWorld *world = new (std::nothrow) PhysicsWorld();
    if (!world) releaseRuntime();
    return world;
}

extern "C" void physics_world_destroy(PhysicsWorld *world)
{
    delete world;
    releaseRuntime();
}

extern "C" uint32_t physics_world_step(PhysicsWorld *world, float dt)
{
    return static_cast<uint32_t>(world->system.Update(dt, 1, &world->temp, &world->jobs));
}

extern "C" bool physics_character_create(PhysicsWorld *world, PhysicsVec3 feet, float radius, float half_height)
{
    const auto capsule = CapsuleShapeSettings(half_height, radius).Create();
    if (!capsule.IsValid()) return false;
    const auto shape = RotatedTranslatedShapeSettings(Vec3(0, half_height + radius, 0), Quat::sIdentity(),
                                                      capsule.Get()).Create();
    if (!shape.IsValid()) return false;

    CharacterVirtualSettings settings;
    settings.mShape = shape.Get();
    settings.mSupportingVolume = Plane(Vec3::sAxisY(), -radius);
    settings.mEnhancedInternalEdgeRemoval = true;
    world->character = new CharacterVirtual(&settings, vec(feet), Quat::sIdentity(), 0, &world->system);
    world->character->RefreshContacts(world->system.GetDefaultBroadPhaseLayerFilter(PHYSICS_DYNAMIC),
                                      world->system.GetDefaultLayerFilter(PHYSICS_DYNAMIC), {}, {}, world->temp);
    return true;
}

extern "C" void physics_character_step(PhysicsWorld *world, float dt, float vx, float vz, bool jump)
{
    CharacterVirtual &character = *world->character;
    character.UpdateGroundVelocity();
    const Vec3 ground_velocity = character.GetGroundVelocity();
    const float vy = character.GetLinearVelocity().GetY();
    Vec3 velocity(vx, vy, vz);
    if (character.GetGroundState() == CharacterVirtual::EGroundState::OnGround && vy - ground_velocity.GetY() < 0.1f) {
        velocity = Vec3(vx, jump ? 4.8f : 0.0f, vz) + ground_velocity;
    }
    const Vec3 gravity = world->system.GetGravity();
    character.SetLinearVelocity(velocity + dt * gravity);
    CharacterVirtual::ExtendedUpdateSettings settings;
    settings.mWalkStairsStepUp = Vec3::sZero();
    character.ExtendedUpdate(dt, gravity, settings, world->system.GetDefaultBroadPhaseLayerFilter(PHYSICS_DYNAMIC),
                             world->system.GetDefaultLayerFilter(PHYSICS_DYNAMIC), {}, {}, world->temp);
}

extern "C" PhysicsCharacterState physics_character_state(const PhysicsWorld *world)
{
    return {pack(world->character->GetPosition()),
            world->character->GetGroundState() == CharacterVirtual::EGroundState::OnGround};
}

extern "C" bool physics_body_create(PhysicsWorld *world, const PhysicsBodyDesc *desc, uint32_t *id)
{
    const ShapeSettings::ShapeResult shape = createShape(*desc);
    if (!shape.IsValid()) return false;

    const bool dynamic = desc->layer == PHYSICS_DYNAMIC;
    const float *q = desc->pose.rotation;
    BodyCreationSettings settings(shape.Get(), vec(desc->pose.position), Quat(q[0], q[1], q[2], q[3]),
                                  dynamic ? EMotionType::Dynamic : EMotionType::Static, desc->layer);
    settings.mLinearVelocity = vec(desc->velocity);
    settings.mAngularVelocity = vec(desc->angular_velocity);
    settings.mMotionQuality = dynamic ? EMotionQuality::LinearCast : EMotionQuality::Discrete;
    settings.mUserData = desc->user_data;
    const BodyID body = world->system.GetBodyInterface().CreateAndAddBody(
        settings, dynamic ? EActivation::Activate : EActivation::DontActivate);
    if (body.IsInvalid()) return false;
    *id = body.GetIndexAndSequenceNumber();
    return true;
}

extern "C" void physics_body_destroy(PhysicsWorld *world, uint32_t id)
{
    BodyInterface &bodies = world->system.GetBodyInterface();
    bodies.RemoveBody(BodyID(id));
    bodies.DestroyBody(BodyID(id));
}

extern "C" void physics_body_state(const PhysicsWorld *world, uint32_t id, PhysicsBodyState *state)
{
    const BodyInterface &bodies = world->system.GetBodyInterface();
    const BodyID body(id);
    RVec3 position;
    Quat rotation;
    bodies.GetPositionAndRotation(body, position, rotation);
    state->pose = {pack(position), {rotation.GetX(), rotation.GetY(), rotation.GetZ(), rotation.GetW()}};
    state->velocity = pack(bodies.GetLinearVelocity(body));
    state->angular_velocity = pack(bodies.GetAngularVelocity(body));
    state->active = bodies.IsActive(body);
}

extern "C" bool physics_raycast(const PhysicsWorld *world, PhysicsVec3 origin, PhysicsVec3 displacement,
                                uint32_t layer_mask, PhysicsRayHit *hit)
{
    const RRayCast ray(vec(origin), vec(displacement));
    RayCastResult result;
    if (!world->system.GetNarrowPhaseQuery().CastRay(ray, result, {}, RayLayerFilter(layer_mask)))
        return false;

    const BodyLockRead lock(world->system.GetBodyLockInterface(), result.mBodyID);
    if (!lock.Succeeded()) return false;
    const Body &body = lock.GetBody();
    const RVec3 position = ray.GetPointOnRay(result.mFraction);
    *hit = {body.GetUserData(), pack(position),
            pack(body.GetWorldSpaceSurfaceNormal(result.mSubShapeID2, position)), result.mFraction};
    return true;
}
