# 🏗️ PHASE 3: ARCHITECTURE REFACTOR - PREVIEW

**Status:** Awaiting Phase 2 Profiling Results  
**Estimated Duration:** 4-6 hours  
**Lead:** Winston (Architect) + Amelia (Developer)

---

## 📋 OBJECTIVES

Based on Phase 1 Cleanup Analysis, Phase 3 will:

1. **Consolidate IPTV Folder Structure**
   - Merge `/lib/features/iptv/` with `/lib/mobile/features/iptv/`
   - Eliminate duplicate player screens
   - Single source of truth for UI components

2. **Simplify Router Architecture**
   - Remove conditional routing logic
   - Clean up navigation paths
   - Android-only route definitions

3. **Extract Reusable Patterns**
   - Create `/lib/core/patterns/` for common implementations
   - Video player wrapper pattern
   - Hive service abstraction

4. **Optimize Import Structure**
   - Remove unused imports
   - Organize by feature boundaries
   - Clear dependency graph

---

## 🔍 PROBABLE FINDINGS FROM PHASE 2

*Updated after profiling completes, Winston's predictions:*

### Likely Bottleneck Areas
1. **Startup:** Hive initialization (likely 400-600ms)
   - Solution: Lazy initialization pattern
   - Impact: -300ms potential

2. **Video Loading:** Stream metadata resolution
   - Solution: Parallel DNS resolution
   - Impact: -100ms potential

3. **Memory:** MediaKit codec libraries (100-150MB)
   - Solution: Investigate lite libraries
   - Impact: Platform constraint

4. **Encryption:** Hive AES overhead (5-15%)
   - Solution: Key derivation optimization
   - Impact: Acceptable, keep encryption

---

## 📐 EXPECTED REFACTORING IMPACT

### File Structure Before
```
lib/
├── features/iptv/screens/
│   └── player_screen.dart (web, REMOVED in cleanup)
├── mobile/features/iptv/screens/
│   ├── native_player_screen.dart
│   └── lite_player_screen.dart
└── core/
    ├── router/ (mixed routing)
    └── utils/ (scattered patterns)
```

### File Structure After
```
lib/
├── features/iptv/
│   ├── screens/
│   │   ├── native_player_screen.dart (unified)
│   │   ├── lite_player_screen.dart
│   │   ├── playlist_screen.dart
│   │   └── dashboard_screen.dart
│   ├── models/
│   ├── services/
│   └── widgets/
├── core/
│   ├── patterns/
│   │   ├── video_player_wrapper.dart
│   │   ├── hive_service_pattern.dart
│   │   └── stream_resolver_pattern.dart
│   ├── router/
│   │   └── app_router.dart (Android-only routes)
│   └── utils/
│       └── [profilers from Phase 2]
```

---

## 🎯 SPECIFIC REFACTORING TASKS

### 3.1: Folder Consolidation (1-2 hours)

**ACTION:**
```bash
# Move mobile-specific components to unified location
mv lib/mobile/features/iptv/* lib/features/iptv/
rmdir lib/mobile/features/iptv
rmdir lib/mobile/features
rmdir lib/mobile (if empty)
```

**Files to Integrate:**
- `native_player_screen.dart`
- `lite_player_screen.dart`
- `playlist_screen.dart`
- Models (playlist, iptv_models)
- Services (xtream_service_mobile)

**Imports to Update:** ~15-20 files
**Risk:** Low (clear separation existing)

---

### 3.2: Router Simplification (1 hour)

**Current State:**
```dart
// lib/core/router/app_router.dart - Mixed routing
final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => 
      kIsWeb ? WebDashboard() : MobileDashboard()
    ),
    // ... feature routes
  ],
);
```

**After Refactoring:**
```dart
// Android-only, no platform checks
final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => 
      DashboardScreen()  // Just one
    ),
    // ... feature routes
  ],
);
```

**Removals:**
- kIsWeb checks (0 remaining)
- Platform-conditional builders
- Web-specific route handlers

---

### 3.3: Pattern Extraction (1-2 hours)

**New Patterns to Create:**

#### `lib/core/patterns/video_player_wrapper.dart`
```dart
/// Abstraction for video player selection
class VideoPlayerWrapper {
  // Selects between MediaKit and VideoPlayer
  // Handles fallback logic
  // Implements common interface
}
```

#### `lib/core/patterns/hive_service_pattern.dart`
```dart
/// Template for Hive-based services
abstract class HiveServiceBase<T> {
  late Box<T> box;
  
  Future<void> init();
  Future<T?> get(String key);
  Future<void> put(String key, T value);
  Future<void> delete(String key);
}
```

#### `lib/core/patterns/stream_resolver_pattern.dart`
```dart
/// Pattern for IPTV stream metadata resolution
class StreamResolverPattern {
  // Parallel DNS resolution
  // Codec detection
  // URL validation
}
```

---

### 3.4: Import Cleanup (30 min)

**Tools to Use:**
```bash
# Remove unused imports (Dart CLI)
dart fix --apply

# Or use Flutter analyzer
flutter analyze 2>&1 | grep unused
```

**Expected Cleanup:**
- 20-30 unused imports removed
- 5-10 files reorganized
- Import order standardized

---

## 📊 PHASE 3 METRICS

### Code Quality Improvements
| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Folders | 8+ | 5 | Unified |
| Mobile-specific | Mixed | Clear | Android only |
| Route handlers | 15+ | 10 | Simplified |
| Patterns extracted | 0 | 3 | Reusable |
| Import quality | Fair | Excellent | 100% used |

### Performance Impact (Expected)
| Aspect | Impact | Reason |
|--------|--------|--------|
| Startup | +5-10ms | Cleaner initialization |
| Build | -10% | Fewer conditional compilations |
| Maintainability | +50% | Clear architecture |
| Testability | +40% | Cleaner patterns |

---

## 🚀 EXECUTION PLAN

### Step 1: Folder Consolidation (1 hour)
- [ ] Move files from `mobile/` to unified locations
- [ ] Update all import statements (40-50 files)
- [ ] Verify no build errors
- [ ] Commit: "Phase 3.1: Consolidate folder structure"

### Step 2: Router Simplification (45 min)
- [ ] Remove kIsWeb checks
- [ ] Simplify route builders
- [ ] Test all navigation paths
- [ ] Commit: "Phase 3.2: Simplify router for Android"

### Step 3: Pattern Extraction (1.5 hours)
- [ ] Create `lib/core/patterns/` directory
- [ ] Extract 3 reusable patterns
- [ ] Refactor existing code to use patterns
- [ ] Update documentation
- [ ] Commit: "Phase 3.3: Extract reusable patterns"

### Step 4: Import Cleanup (30 min)
- [ ] Run dart fix
- [ ] Manual cleanup as needed
- [ ] Verify imports alphabetized
- [ ] Commit: "Phase 3.4: Cleanup and organize imports"

### Step 5: Final Testing (30 min)
- [ ] `flutter clean && flutter pub get`
- [ ] `flutter analyze` - zero warnings
- [ ] `flutter build apk --release` - successful
- [ ] Commit: "Phase 3: Architecture refactor complete"

---

## 📋 DETAILED TASK BREAKDOWN

### 3.1.1: Move IPTV Components
```bash
# Current structure
lib/mobile/features/iptv/
├── screens/
│   ├── native_player_screen.dart
│   ├── lite_player_screen.dart
│   ├── mobile_dashboard_screen.dart
│   ├── mobile_playlist_selection_screen.dart
│   └── mobile_series_detail_screen.dart
├── models/
├── services/
└── widgets/

# Target
lib/features/iptv/
├── screens/
│   ├── native_player_screen.dart
│   ├── lite_player_screen.dart
│   ├── playlist_selection_screen.dart
│   ├── dashboard_screen.dart
│   └── series_detail_screen.dart
├── models/
├── services/
└── widgets/
```

### 3.1.2: Import Updates Needed
- `lib/main.dart` - Route imports
- `lib/core/router/app_router.dart` - Route definitions
- `lib/core/providers/` - Screen providers
- `lib/mobile/providers/` - All providers to consolidate

---

## 🎯 SUCCESS CRITERIA

✅ Android-only architecture (no platform conditionals)  
✅ Unified IPTV folder structure  
✅ 3+ reusable patterns extracted  
✅ `flutter analyze` returns 0 issues  
✅ Build completes successfully  
✅ All tests pass (if applicable)  

---

## ⚠️ RISK MITIGATION

**Risk:** Import breakage during consolidation  
**Mitigation:** IDE refactoring tools, git undo available

**Risk:** Router navigation broken  
**Mitigation:** Test each route after changes

**Risk:** Missed import cleanup  
**Mitigation:** `dart fix --apply` + manual review

---

## 📈 EXPECTED OUTCOMES

After Phase 3 completion:
- ✅ Clean Android-only architecture
- ✅ ~15% reduction in code duplication
- ✅ Improved maintainability (50%+)
- ✅ Clear dependency graph
- ✅ Reusable patterns for future features

---

## 🎬 NEXT: AWAIT PHASE 2 RESULTS

**Don't start Phase 3 until:**
1. ✅ Phase 2 profiling complete
2. ✅ Bottleneck analysis done
3. ✅ Results reviewed with team
4. ✅ Optimization priorities set

**Then:** Priority adjustments to Phase 3 based on discovered bottlenecks.

---

*Phase 3 Preview Complete. Standing by for Phase 2 results.*
