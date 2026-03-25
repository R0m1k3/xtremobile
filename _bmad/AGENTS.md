# 🤖 BMAD Agents Configuration - XtremFlow IPTV

## Installed Agents

```
✅ BMAD Core (v6.2.1)
✅ BMM Module (v6.2.1) - Core agile development
✅ Claude Code (43 skills)
```

---

## 🎯 XtremFlow Agent Assignments

### Phase 1: Infrastructure & Security (Week 1)

#### Task 1.1: Logging System (Days 1-2)
**Primary**: @developer
**Secondary**: @architect, @qa
**Reference**: `IMPLEMENTATION_GUIDE.md` → Section 1

```bash
@developer Implement LoggingService for XtremFlow backend.
Reference: IMPLEMENTATION_GUIDE.md Section 1.2-1.3
Tasks:
1. Create bin/services/logging_service.dart
2. Replace print() with logging calls
3. Add request ID tracing
Files: bin/services/logging_service.dart, bin/middleware/logging_middleware.dart
```

#### Task 1.2: Error Handling System (Day 2)
**Primary**: @developer
**Secondary**: @architect, @qa
**Reference**: `IMPLEMENTATION_GUIDE.md` → Section 2

```bash
@developer Implement unified error handling for XtremFlow.
Files to create/modify:
1. bin/utils/app_exceptions.dart (NEW)
2. bin/middleware/error_handler.dart (NEW)
3. lib/core/utils/app_exceptions.dart (NEW)
Integrate with all API endpoints
```

#### Task 1.3: Authentication Hardening (Days 2-4)
**Primary**: @developer
**Secondary**: @security-expert, @architect
**Reference**: `IMPLEMENTATION_GUIDE.md` → Section 3

```bash
@security-expert Review authentication design.
Concerns: Password hashing, JWT tokens, session management

@developer Implement secure authentication:
1. Replace SHA-256 with bcrypt (IMPLEMENTATION_GUIDE.md 3.2)
2. Add JWT token service (IMPLEMENTATION_GUIDE.md 3.3)
3. Update auth handler (IMPLEMENTATION_GUIDE.md 3.4)
Critical: Start with @architect for design review
```

#### Task 1.4: Database Reliability (Days 4-5)
**Primary**: @architect
**Secondary**: @developer, @data-architect
**Reference**: `IMPLEMENTATION_GUIDE.md` → Section 4

```bash
@architect Design database reliability improvements:
1. Migration system strategy
2. Backup & recovery architecture
3. Encryption approach

@developer Implement:
1. Migrations system (IMPLEMENTATION_GUIDE.md 4.1)
2. Backup service (IMPLEMENTATION_GUIDE.md 4.2)
3. Integration with server.dart
```

---

### Phase 2: Monitoring & Testing (Week 1-2)

#### Task 2.1: Health & Metrics
**Primary**: @architect
**Secondary**: @developer
**Reference**: `IMPROVEMENT_PLAN.md` → Level 2.1

```bash
@architect Design health check endpoint:
- Request rate metrics
- Error tracking
- Database status
- Process health

@developer Implement monitoring endpoints
```

#### Task 2.2: Test Architecture
**Primary**: @qa
**Secondary**: @architect, @developer
**Reference**: `IMPROVEMENT_PLAN.md` → Level 2.2

```bash
@qa Create comprehensive test strategy:
- Unit tests for auth, database
- Integration tests for APIs
- Flutter widget tests
Target: 80%+ coverage

@developer Generate test files
```

---

### Phase 3: Architecture Modernization (Week 2-3)

#### Task 3.1: Clean Architecture
**Primary**: @architect (CRITICAL)
**Secondary**: @developer, @code-reviewer
**Reference**: `IMPROVEMENT_PLAN.md` → Level 3.1

```bash
@architect Design new project structure:
- Refactor to Clean Architecture
- Define layer boundaries
- Plan migration strategy
Major refactor - requires careful planning

Schema:
lib/
  core/
  shared/
  features/
    auth/
      data/
      domain/
      presentation/
```

#### Task 3.2: State Management
**Primary**: @architect
**Secondary**: @developer
**Reference**: `IMPROVEMENT_PLAN.md` → Level 3.2

```bash
@architect Review Riverpod usage:
- @riverpod annotations
- Family modifiers
- Error handling patterns

@developer Refactor providers for optimization
```

---

## 🔄 Workflow Templates

### Template: Implement Feature from IMPROVEMENT_PLAN.md

1. **Reference Document**
   - IMPROVEMENT_PLAN.md (identify level/item)
   - PROBLEMS_AND_SOLUTIONS.md (if related to problem)

2. **Create Analysis**
   ```bash
   @analyst Create analysis for: {feature name}
   Output: _bmad-output/planning-artifacts/{feature}-analysis.md
   ```

3. **Create Plan**
   ```bash
   @pm Create implementation plan from IMPROVEMENT_PLAN.md Section {X}
   Output: _bmad-output/planning-artifacts/{feature}-plan.md
   ```

4. **Design Architecture**
   ```bash
   @architect Design technical solution
   Reference documents provided
   Output: _bmad-output/implementation-artifacts/{feature}-design.md
   ```

5. **Implement**
   ```bash
   @developer Implement based on plan and design
   Reference: IMPLEMENTATION_GUIDE.md Section {Y}
   ```

6. **Test**
   ```bash
   @qa Create test strategy and implementation
   Target coverage: 80%+
   ```

7. **Review**
   ```bash
   @code-reviewer Review implementation against design
   ```

---

## 📋 Document Inventory

### Primary Planning Documents
- `IMPROVEMENT_PLAN.md` - 5-level improvement roadmap (26 items)
- `IMPLEMENTATION_GUIDE.md` - Code-level recipes with exact implementations
- `PROBLEMS_AND_SOLUTIONS.md` - 26 identified problems with solutions

### BMad Output Directories
- `_bmad-output/planning-artifacts/` - Plans, analyses, user stories
- `_bmad-output/implementation-artifacts/` - Technical designs, architecture
- `docs/` - Project knowledge repository

---

## 🎯 Agent Skill Mapping for XtremFlow

### Backend Development (Dart Server)
- **Logger Package Integration**: @developer (3.2-4 hours)
- **Exception Handling**: @developer (2-3 hours)
- **Authentication (Bcrypt + JWT)**: @security-expert → @developer (4-5 hours)
- **Migrations System**: @architect → @developer (3-4 hours)
- **Backup Service**: @developer (2-3 hours)
- **Error Middleware**: @developer (2-3 hours)
- **API Documentation**: @tech-writer (6-8 hours)

### Frontend Development (Flutter)
- **Error Boundary Widgets**: @developer (2-3 hours)
- **Provider Optimization**: @architect → @developer (4-5 hours)
- **Error UI Components**: @developer (3-4 hours)
- **Offline Support**: @architect → @developer (5-6 hours)

### Infrastructure
- **CI/CD Pipeline**: @devops-engineer (4-6 hours)
- **Docker Optimization**: @devops-engineer (3-4 hours)
- **Monitoring Setup**: @devops-engineer (4-5 hours)

### Quality Assurance
- **Unit Tests**: @qa (10-15 hours)
- **Integration Tests**: @qa (8-10 hours)
- **Widget Tests**: @qa (6-8 hours)
- **Security Testing**: @security-expert (8-10 hours)

---

## 🏃 Quick Start Workflows

### Scenario: "I have 1 day to improve XtremFlow"

```bash
Day 1 Priority:
1. @analyst (15 min): Analyze current state
2. @pm (30 min): Create priority list
3. @developer (6 hours): Implement logging + error handling
4. @qa (1.5 hours): Create basic tests
5. @devops-engineer (30 min): Update Docker healthcheck

Objective: Get Logging + Error Handling + Basic Tests working
```

### Scenario: "I have 1 week"

```bash
Day 1: Logging system - @developer
Day 2: Error handling + Auth design - @security-expert + @developer
Day 3-4: Backend auth implementation - @developer + @security-expert
Day 5: Database migrations - @architect + @developer
Day 6-7: Tests + integration - @qa + @developer

Result: Phase 1 complete - Ready for Phase 2
```

### Scenario: "I have 3 weeks"

```bash
Week 1: Phase 1 (Infrastructure)
  - Logging, Error Handling, Auth, Database

Week 2: Phase 2 (Testing & Monitoring)
  - Test Architecture implementation
  - Monitoring setup
  - Performance optimization

Week 3: Phase 3 (Architecture)
  - Clean Architecture refactoring (planning only)
  - State Management optimization
  - Documentation

Result: 60%+ of IMPROVEMENT_PLAN complete
```

---

## 🔐 Security Considerations

When implementing security-critical features (#1.3: Auth, #24-26: Input Validation, CORS, CSRF):

1. **ALWAYS** involve @security-expert
2. **ALWAYS** request comprehensive test coverage
3. **ALWAYS** create security audit checklist
4. **ALWAYS** document attack surface analysis
5. **Reference**: PROBLEMS_AND_SOLUTIONS.md critical section

```bash
Example - Secure Implementation Pattern:

@security-expert:
  "Create security audit checklist for JWT implementation"
  → Identify OWASP Top 10 risks for this feature

@architect:
  "Design JWT flow with attack surface mitigation"
  → Create threat model

@developer:
  "Implement with security-first approach"
  → Code review with @security-expert

@qa:
  "Create security test cases"
  → Penetration testing scenarios
```

---

## 💻 Usage in VS Code Claude Code

### Invoke Single Agent
```
@developer Implement logging service from IMPLEMENTATION_GUIDE.md Section 1.2
```

### Invoke Agent Team
```
@architect: Design database migrations
@developer: Implement migrations system
@qa: Create migration tests
Reference: IMPLEMENTATION_GUIDE.md Section 4.1
```

### Invoke with Workflow
```
Follow the BMad workflow to implement JWT authentication:
1. Analysis phase: @analyst - Current auth state
2. Planning phase: @pm - Implementation roadmap
3. Design phase: @architect - JWT flow design
4. Implementation phase: @developer - JWT service code
5. Testing phase: @qa - Auth tests
Reference: IMPLEMENTATION_GUIDE.md Section 3
```

### Ask for Help
```
@bmad-help I just implemented logging, what should I do next?
```

---

## 📍 Status Tracking Checklist

```
PHASE 1: Infrastructure (Week 1)
  [ ] 1.1 Logging System
      - [ ] logger package added
      - [ ] LoggingService class created
      - [ ] File handler configured
      - [ ] All print() replaced
      - [ ] Unit tests created
  
  [ ] 1.2 Error Handling
      - [ ] AppException hierarchy created
      - [ ] ErrorHandler middleware implemented
      - [ ] All endpoints return proper errors
      - [ ] Error UI components created
      - [ ] Error documentation complete
  
  [ ] 1.3 Authentication
      - [ ] Bcrypt integrated
      - [ ] JWT service created
      - [ ] Session model updated
      - [ ] Auth handler updated
      - [ ] 2FA placeholder added
      - [ ] Security audit passed
  
  [ ] 1.4 Database
      - [ ] Migrations system working
      - [ ] Backup service running
      - [ ] Encryption enabled
      - [ ] Cleanup service active
      - [ ] Database tests passing

PHASE 2: Testing & Monitoring (Week 2)
  [ ] Unit tests (80%+ coverage)
  [ ] Integration tests
  [ ] CI/CD pipeline
  [ ] Monitoring endpoints

PHASE 3+: Architecture (Week 3+)
  [ ] Clean Architecture refactor
  [ ] Advanced features
```

---

## 🚀 Next Steps

1. **Review this document** with your team
2. **Start with Phase 1.1**: Logging System
   ```bash
   @developer I'm ready to implement logging. Where do we start?
   ```
3. **Follow the workflow** for each task
4. **Update status checklist** as you progress
5. **Use `@bmad-help`** for contextual guidance

---

*BMAD Agents Configuration*
*Created: 2026-03-25*
*Framework: BMad Method v6.2.1*
