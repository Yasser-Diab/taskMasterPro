-- Idempotent production-data installation for DayVector v0.0.27.
--
-- This is an operational seed, not a schema migration and not a reset script.
-- It never derives ownership from an email address. The configured owner UUID
-- must already exist in auth.users before any application-owned rows are
-- created or updated.
--
-- Planned start: 2026-08-01
-- Time zone: Africa/Cairo
-- Umbrella plan: Integrated Full-Stack Programming and German Roadmap

do $seed$
#variable_conflict use_variable
declare
  owner_id constant uuid := '4bd3e32d-1dcd-48ed-9f64-9099675047f1';
  plan_start constant date := date '2026-08-01';
  installed_release constant text := '0.0.27';
  umbrella_title constant text :=
    'Integrated Full-Stack Programming and German Roadmap';
  plans constant jsonb := $plans$
  [
    {
      "key": "full_stack_programming",
      "title": "Full-Stack Programming",
      "description": "A sustainable, evidence-based path from environment setup through JavaScript, professional front-end work, React and TypeScript, back-end APIs, PostgreSQL, Full Stack Open, a production capstone, and employment preparation.",
      "outcome": "Employable junior full-stack developer with a production-quality portfolio",
      "target_days": 847,
      "required_effort_hours": 1450,
      "weekly_target_hours": "11–12",
      "target_summary": "Employable junior full-stack developer in approximately 22–28 months",
      "study_cycle": ["Hsoub explanation","freeCodeCamp exercises","official documentation","independent project","GitHub deployment and README"],
      "initial_eight_week_focus": ["Resume Spam Filter Step 20","Create the learning repository","Complete Introduction to GitHub","Build an independent spam detector","Build a palindrome checker","Build a form validator","Build a quiz application","Build and deploy an API search interface"],
      "full_stack_open_cost": "Free",
      "phases": [
        {
          "key": "p0",
          "title": "Phase 0 — Setup and Baseline",
          "duration": "1 week",
          "days": 7,
          "milestone": "Development environment and learning repository ready",
          "checkpoints": [
            "GitHub, Node.js, Visual Studio Code, and browser tools are verified",
            "Learning-roadmap repository uses the agreed folder structure",
            "Baseline development workflow is documented"
          ],
          "tasks": [
            {"title":"Create or verify your GitHub account","minutes":45,"mode":"checklist","resource_name":"GitHub","url":"https://github.com/"},
            {"title":"Complete GitHub’s introductory exercises","minutes":90,"mode":"checklist","resource_name":"Introduction to GitHub","url":"https://github.com/skills/introduction-to-github"},
            {"title":"Study GitHub Skills catalogue","minutes":60,"mode":"continuous","resource_name":"GitHub Skills","url":"https://github.com/skills"},
            {"title":"Install Node.js using the official download page","minutes":45,"mode":"checklist","resource_name":"Node.js download","url":"https://nodejs.org/en/download"},
            {"title":"Install Visual Studio Code","minutes":45,"mode":"checklist","resource_name":"Visual Studio Code","url":"https://code.visualstudio.com/"},
            {"title":"Review development-environment basics","minutes":90,"mode":"continuous","resource_name":"MDN environment setup","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Getting_started/Environment_setup"},
            {"title":"Create a learning-roadmap repository","minutes":90,"mode":"checklist","resource_name":"Create a GitHub repository","url":"https://github.com/new"}
          ]
        },
        {
          "key": "p1",
          "title": "Phase 1 — Complete JavaScript Fundamentals",
          "duration": "10–12 weeks",
          "days": 84,
          "milestone": "freeCodeCamp JavaScript certification and independent fundamentals projects completed",
          "checkpoints": [
            "Explain scope, closures, callbacks, promises, and async/await",
            "Manipulate the DOM and validate forms",
            "Fetch and display API data with loading, success, empty, and error states",
            "Store data in local storage",
            "Debug using browser developer tools",
            "Complete the freeCodeCamp JavaScript certification",
            "Deploy independent projects with useful README files"
          ],
          "tasks": [
            {"title":"Resume the Spam Filter workshop from Step 20","minutes":180,"mode":"pomodoro","resource_name":"freeCodeCamp Spam Filter Step 20","url":"https://www.freecodecamp.org/learn/javascript-v9/workshop-spam-filter/step-20"},
            {"title":"Finish Basic Regular Expressions","minutes":240,"mode":"pomodoro","resource_name":"freeCodeCamp JavaScript certification","url":"https://www.freecodecamp.org/learn/javascript-v9/"},
            {"title":"Complete the remaining JavaScript lessons, workshops, labs, reviews, and projects","minutes":3000,"mode":"pomodoro","resource_name":"freeCodeCamp JavaScript certification","url":"https://www.freecodecamp.org/learn/javascript-v9/"},
            {"title":"Study JavaScript sections in Hsoub","minutes":1080,"mode":"pomodoro","resource_name":"Hsoub Front-End Development","url":"https://academy.hsoub.com/learn/front-end-web-development/"},
            {"title":"Study JavaScript through MDN","minutes":600,"mode":"continuous","resource_name":"MDN Core Scripting","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Scripting"},
            {"title":"Review regular expressions","minutes":120,"mode":"continuous","resource_name":"MDN Regular expressions","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_expressions"},
            {"title":"Review array methods","minutes":150,"mode":"continuous","resource_name":"MDN Array reference","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array"},
            {"title":"Review functions and closures","minutes":180,"mode":"continuous","resource_name":"MDN Functions guide","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Functions"},
            {"title":"Learn promises","minutes":180,"mode":"continuous","resource_name":"MDN Using promises","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Using_promises"},
            {"title":"Learn async and await","minutes":180,"mode":"continuous","resource_name":"MDN async function","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/async_function"},
            {"title":"Learn Fetch API","minutes":240,"mode":"pomodoro","resource_name":"MDN Using Fetch","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch"},
            {"title":"Learn browser storage","minutes":120,"mode":"continuous","resource_name":"MDN localStorage","url":"https://developer.mozilla.org/en-US/docs/Web/API/Window/localStorage"},
            {"title":"Rebuild the spam filter without copying the freeCodeCamp result","minutes":360,"mode":"pomodoro","resource_name":"MDN Regular expressions","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_expressions"},
            {"title":"Build a palindrome checker","minutes":240,"mode":"pomodoro","resource_name":"MDN String reference","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String"},
            {"title":"Build a form validator","minutes":360,"mode":"pomodoro","resource_name":"MDN client-side form validation","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Extensions/Forms/Form_validation"},
            {"title":"Build an expense tracker using local storage","minutes":600,"mode":"pomodoro","resource_name":"MDN Web Storage API","url":"https://developer.mozilla.org/en-US/docs/Web/API/Web_Storage_API"},
            {"title":"Build a quiz application","minutes":480,"mode":"pomodoro","resource_name":"MDN DOM events","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Scripting/Events"},
            {"title":"Build an API search application","minutes":600,"mode":"pomodoro","resource_name":"MDN Fetch API","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API"}
          ]
        },
        {
          "key": "p2",
          "title": "Phase 2 — Professional Front-End Development",
          "duration": "12 weeks",
          "days": 84,
          "milestone": "Professional vanilla-JavaScript interfaces completed",
          "checkpoints": [
            "Use semantic HTML and accessible navigation",
            "Build responsive layouts with Flexbox and Grid",
            "Handle API loading, success, empty, and failure states",
            "Use Git branches, pull requests, and GitHub Pages",
            "Support keyboard navigation and mobile layouts",
            "Deliver Arabic and English interface layouts"
          ],
          "tasks": [
            {"title":"Continue the Hsoub Front-End Development course","minutes":2880,"mode":"pomodoro","resource_name":"Hsoub Front-End Development","url":"https://academy.hsoub.com/learn/front-end-web-development/"},
            {"title":"Complete MDN Core modules","minutes":1440,"mode":"pomodoro","resource_name":"MDN Core modules","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core"},
            {"title":"Review semantic HTML","minutes":180,"mode":"continuous","resource_name":"MDN Structuring content","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Structuring_content"},
            {"title":"Review CSS fundamentals","minutes":240,"mode":"continuous","resource_name":"MDN Styling basics","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Styling_basics"},
            {"title":"Master Flexbox","minutes":300,"mode":"pomodoro","resource_name":"MDN Flexbox","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Flexbox"},
            {"title":"Master CSS Grid","minutes":300,"mode":"pomodoro","resource_name":"MDN Grids","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Grids"},
            {"title":"Study responsive design","minutes":240,"mode":"pomodoro","resource_name":"MDN Responsive Design","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Responsive_Design"},
            {"title":"Study accessibility","minutes":300,"mode":"continuous","resource_name":"MDN Accessibility","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Accessibility"},
            {"title":"Study web forms","minutes":300,"mode":"pomodoro","resource_name":"MDN Web forms","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Extensions/Forms"},
            {"title":"Learn Git branching and pull-request review","minutes":180,"mode":"checklist","resource_name":"GitHub Skills review pull requests","url":"https://github.com/skills/review-pull-requests"},
            {"title":"Learn deployment with GitHub Pages","minutes":180,"mode":"checklist","resource_name":"GitHub Pages documentation","url":"https://docs.github.com/en/pages"},
            {"title":"Build a responsive company website","minutes":900,"mode":"pomodoro","resource_name":"MDN Learn Web Development","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/"},
            {"title":"Build an administrative dashboard","minutes":1200,"mode":"pomodoro","resource_name":"MDN CSS layout","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout"},
            {"title":"Build a product catalogue","minutes":900,"mode":"pomodoro","resource_name":"MDN Fetch API","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API"},
            {"title":"Build a glass-order interface prototype","minutes":1200,"mode":"pomodoro","resource_name":"MDN Web application guidance","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/"}
          ]
        },
        {
          "key": "p3",
          "title": "Phase 3 — React and TypeScript",
          "duration": "14–16 weeks",
          "days": 112,
          "milestone": "Production-style typed React applications completed",
          "checkpoints": [
            "Build components using JSX and typed props",
            "Manage events, state, forms, and derived state correctly",
            "Use effects only for external synchronization",
            "Model API data with TypeScript",
            "Narrow types and build reusable generics",
            "Complete the required front-end library projects"
          ],
          "tasks": [
            {"title":"Start freeCodeCamp Front-End Development Libraries","minutes":2100,"mode":"pomodoro","resource_name":"freeCodeCamp Front-End Development Libraries","url":"https://www.freecodecamp.org/learn/front-end-development-libraries-v9/"},
            {"title":"Complete React Quick Start","minutes":180,"mode":"pomodoro","resource_name":"React Learn","url":"https://react.dev/learn"},
            {"title":"Learn components, JSX, and props","minutes":240,"mode":"pomodoro","resource_name":"React Describing the UI","url":"https://react.dev/learn/describing-the-ui"},
            {"title":"Learn events and state","minutes":300,"mode":"pomodoro","resource_name":"React Adding Interactivity","url":"https://react.dev/learn/adding-interactivity"},
            {"title":"Learn state management principles","minutes":300,"mode":"pomodoro","resource_name":"React Managing State","url":"https://react.dev/learn/managing-state"},
            {"title":"Learn effects correctly","minutes":240,"mode":"continuous","resource_name":"React Synchronizing with Effects","url":"https://react.dev/learn/synchronizing-with-effects"},
            {"title":"Learn when effects are unnecessary","minutes":180,"mode":"continuous","resource_name":"React You Might Not Need an Effect","url":"https://react.dev/learn/you-might-not-need-an-effect"},
            {"title":"Complete Thinking in React","minutes":240,"mode":"pomodoro","resource_name":"Thinking in React","url":"https://react.dev/learn/thinking-in-react"},
            {"title":"Start the TypeScript Handbook","minutes":180,"mode":"continuous","resource_name":"TypeScript Handbook","url":"https://www.typescriptlang.org/docs/handbook/intro.html"},
            {"title":"Learn TypeScript basics","minutes":240,"mode":"pomodoro","resource_name":"TypeScript Basic Types","url":"https://www.typescriptlang.org/docs/handbook/2/basic-types.html"},
            {"title":"Learn everyday TypeScript types","minutes":240,"mode":"pomodoro","resource_name":"TypeScript Everyday Types","url":"https://www.typescriptlang.org/docs/handbook/2/everyday-types.html"},
            {"title":"Learn type narrowing","minutes":240,"mode":"pomodoro","resource_name":"TypeScript Narrowing","url":"https://www.typescriptlang.org/docs/handbook/2/narrowing.html"},
            {"title":"Learn object types","minutes":240,"mode":"pomodoro","resource_name":"TypeScript Object Types","url":"https://www.typescriptlang.org/docs/handbook/2/objects.html"},
            {"title":"Learn generics","minutes":300,"mode":"pomodoro","resource_name":"TypeScript Generics","url":"https://www.typescriptlang.org/docs/handbook/2/generics.html"},
            {"title":"Build a React expense manager","minutes":900,"mode":"pomodoro","resource_name":"React Learn","url":"https://react.dev/learn"},
            {"title":"Build a weather dashboard","minutes":720,"mode":"pomodoro","resource_name":"MDN Fetch API","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API"},
            {"title":"Build a typed product-management interface","minutes":1200,"mode":"pomodoro","resource_name":"TypeScript Handbook","url":"https://www.typescriptlang.org/docs/handbook/intro.html"},
            {"title":"Build a DayVector front-end prototype","minutes":1200,"mode":"pomodoro","resource_name":"React Managing State","url":"https://react.dev/learn/managing-state"},
            {"title":"Build a typed forms and validation project","minutes":720,"mode":"pomodoro","resource_name":"React input documentation","url":"https://react.dev/reference/react-dom/components/input"}
          ]
        },
        {
          "key": "p4",
          "title": "Phase 4 — Back-End Development and APIs",
          "duration": "12–14 weeks",
          "days": 98,
          "milestone": "Secure, validated, documented, and tested APIs completed",
          "checkpoints": [
            "Validate every API input",
            "Implement authentication and authorization",
            "Use centralized error handling",
            "Keep secrets in environment variables",
            "Add useful logging",
            "Write automated tests",
            "Return consistent response structures",
            "Document the public API"
          ],
          "tasks": [
            {"title":"Start freeCodeCamp Back-End Development and APIs","minutes":2400,"mode":"pomodoro","resource_name":"freeCodeCamp Back-End Development and APIs","url":"https://www.freecodecamp.org/learn/back-end-development-and-apis-v9/"},
            {"title":"Study the official Node.js introduction","minutes":240,"mode":"continuous","resource_name":"Node.js Learn","url":"https://nodejs.org/en/learn"},
            {"title":"Learn Node.js command-line usage","minutes":180,"mode":"pomodoro","resource_name":"Node.js command line","url":"https://nodejs.org/en/learn/command-line"},
            {"title":"Learn asynchronous Node.js programming","minutes":300,"mode":"pomodoro","resource_name":"Node.js asynchronous work","url":"https://nodejs.org/en/learn/asynchronous-work"},
            {"title":"Study Express installation and setup","minutes":120,"mode":"continuous","resource_name":"Express installation","url":"https://expressjs.com/en/5x/starter/installing.html"},
            {"title":"Create an Express Hello World application","minutes":120,"mode":"pomodoro","resource_name":"Express Hello World","url":"https://expressjs.com/en/starter/hello-world.html"},
            {"title":"Learn Express routing","minutes":240,"mode":"pomodoro","resource_name":"Express routing","url":"https://expressjs.com/en/guide/routing.html"},
            {"title":"Learn middleware","minutes":240,"mode":"pomodoro","resource_name":"Express middleware","url":"https://expressjs.com/en/guide/using-middleware.html"},
            {"title":"Learn error handling","minutes":240,"mode":"pomodoro","resource_name":"Express error handling","url":"https://expressjs.com/en/guide/error-handling.html"},
            {"title":"Study HTTP methods and status codes","minutes":240,"mode":"continuous","resource_name":"MDN HTTP","url":"https://developer.mozilla.org/en-US/docs/Web/HTTP"},
            {"title":"Study REST API design through Full Stack Open Part 3","minutes":360,"mode":"pomodoro","resource_name":"Full Stack Open Part 3","url":"https://fullstackopen.com/en/part3"},
            {"title":"Learn API testing through Full Stack Open Part 4","minutes":360,"mode":"pomodoro","resource_name":"Full Stack Open Part 4","url":"https://fullstackopen.com/en/part4"},
            {"title":"Build a Notes REST API","minutes":720,"mode":"pomodoro","resource_name":"Express routing","url":"https://expressjs.com/en/guide/routing.html"},
            {"title":"Build a user registration and authentication API","minutes":900,"mode":"pomodoro","resource_name":"OWASP Authentication Cheat Sheet","url":"https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html"},
            {"title":"Build a task and roadmap API","minutes":1200,"mode":"pomodoro","resource_name":"Full Stack Open Part 3","url":"https://fullstackopen.com/en/part3"},
            {"title":"Build a file upload API","minutes":720,"mode":"pomodoro","resource_name":"OWASP File Upload Cheat Sheet","url":"https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html"},
            {"title":"Build an API test suite","minutes":900,"mode":"pomodoro","resource_name":"Full Stack Open Part 4","url":"https://fullstackopen.com/en/part4"},
            {"title":"Write API documentation","minutes":480,"mode":"continuous","resource_name":"MDN HTTP","url":"https://developer.mozilla.org/en-US/docs/Web/HTTP"}
          ]
        },
        {
          "key": "p5",
          "title": "Phase 5 — SQL and PostgreSQL",
          "duration": "8–10 weeks",
          "days": 70,
          "milestone": "DayVector relational database designed and implemented",
          "checkpoints": [
            "Entity-relationship diagram completed before table implementation",
            "Relationships and normalization are explained",
            "Queries, joins, aggregates, and window functions work",
            "Foreign keys, transactions, migrations, and indexes are present",
            "DayVector application entities have explicit ownership and access rules"
          ],
          "tasks": [
            {"title":"Start freeCodeCamp Relational Databases","minutes":1800,"mode":"pomodoro","resource_name":"freeCodeCamp Relational Databases","url":"https://www.freecodecamp.org/learn/relational-databases-v9/"},
            {"title":"Start the official PostgreSQL tutorial","minutes":180,"mode":"continuous","resource_name":"PostgreSQL Tutorial","url":"https://www.postgresql.org/docs/current/tutorial.html"},
            {"title":"Learn to create tables","minutes":180,"mode":"pomodoro","resource_name":"PostgreSQL Creating a New Table","url":"https://www.postgresql.org/docs/current/tutorial-table.html"},
            {"title":"Learn querying","minutes":240,"mode":"pomodoro","resource_name":"PostgreSQL Querying a Table","url":"https://www.postgresql.org/docs/current/tutorial-select.html"},
            {"title":"Learn joins","minutes":240,"mode":"pomodoro","resource_name":"PostgreSQL Joins","url":"https://www.postgresql.org/docs/current/tutorial-join.html"},
            {"title":"Learn aggregate functions","minutes":180,"mode":"pomodoro","resource_name":"PostgreSQL Aggregate Functions","url":"https://www.postgresql.org/docs/current/tutorial-agg.html"},
            {"title":"Learn foreign keys","minutes":180,"mode":"pomodoro","resource_name":"PostgreSQL Foreign Keys","url":"https://www.postgresql.org/docs/current/tutorial-fk.html"},
            {"title":"Learn transactions","minutes":240,"mode":"pomodoro","resource_name":"PostgreSQL Transactions","url":"https://www.postgresql.org/docs/current/tutorial-transactions.html"},
            {"title":"Learn window functions","minutes":240,"mode":"pomodoro","resource_name":"PostgreSQL Window Functions","url":"https://www.postgresql.org/docs/current/tutorial-window.html"},
            {"title":"Study relational databases in Full Stack Open Part 13","minutes":480,"mode":"pomodoro","resource_name":"Full Stack Open Part 13","url":"https://fullstackopen.com/en/part13"},
            {"title":"Design the DayVector database and entity-relationship diagram","minutes":1200,"mode":"pomodoro","resource_name":"PostgreSQL Data Definition","url":"https://www.postgresql.org/docs/current/ddl.html"}
          ]
        },
        {
          "key": "p6",
          "title": "Phase 6 — Full Stack Open",
          "duration": "20–24 weeks",
          "days": 168,
          "milestone": "Core Full Stack Open curriculum completed in the required order",
          "checkpoints": [
            "React, Node.js, REST APIs, testing, and TypeScript are integrated",
            "CI/CD and container workflows are demonstrated",
            "Relational database work is completed",
            "GraphQL and React Native remain optional until the main web application works"
          ],
          "tasks": [
            {"title":"Complete Full Stack Open Part 0 — Fundamentals of Web Apps","minutes":660,"mode":"pomodoro","resource_name":"Full Stack Open Part 0","url":"https://fullstackopen.com/en/part0"},
            {"title":"Complete Full Stack Open Part 1 — Introduction to React","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 1","url":"https://fullstackopen.com/en/part1"},
            {"title":"Complete Full Stack Open Part 2 — Communicating with Server","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 2","url":"https://fullstackopen.com/en/part2"},
            {"title":"Complete Full Stack Open Part 3 — Programming a Server","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 3","url":"https://fullstackopen.com/en/part3"},
            {"title":"Complete Full Stack Open Part 4 — Testing Express Servers","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 4","url":"https://fullstackopen.com/en/part4"},
            {"title":"Complete Full Stack Open Part 5 — Testing React Apps","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 5","url":"https://fullstackopen.com/en/part5"},
            {"title":"Complete Full Stack Open Part 7 — React Router and State Management","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 7","url":"https://fullstackopen.com/en/part7"},
            {"title":"Complete Full Stack Open Part 9 — TypeScript","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 9","url":"https://fullstackopen.com/en/part9"},
            {"title":"Complete Full Stack Open Part 11 — CI/CD","minutes":1320,"mode":"pomodoro","resource_name":"Full Stack Open Part 11","url":"https://fullstackopen.com/en/part11"},
            {"title":"Complete Full Stack Open Part 12 — Containers","minutes":1320,"mode":"pomodoro","resource_name":"Full Stack Open Part 12","url":"https://fullstackopen.com/en/part12"},
            {"title":"Complete Full Stack Open Part 13 — Relational Databases","minutes":1980,"mode":"pomodoro","resource_name":"Full Stack Open Part 13","url":"https://fullstackopen.com/en/part13"},
            {"title":"Optionally complete Full Stack Open Part 6 — Advanced State Management","minutes":1320,"mode":"pomodoro","resource_name":"Full Stack Open Part 6","url":"https://fullstackopen.com/en/part6"},
            {"title":"Optionally complete Full Stack Open Part 8 — GraphQL after the web application works","minutes":1320,"mode":"pomodoro","resource_name":"Full Stack Open Part 8","url":"https://fullstackopen.com/en/part8"},
            {"title":"Optionally complete Full Stack Open Part 10 — React Native after the web application works","minutes":1320,"mode":"pomodoro","resource_name":"Full Stack Open Part 10","url":"https://fullstackopen.com/en/part10"}
          ]
        },
        {
          "key": "p7",
          "title": "Phase 7 — Full-Stack Capstone",
          "duration": "14–16 weeks",
          "days": 112,
          "milestone": "DayVector full-stack MVP completed through controlled releases",
          "checkpoints": [
            "Authentication and profile ownership are secure",
            "Tasks, roadmaps, recurrence, timers, and interruptions work",
            "PostgreSQL reports use canonical data",
            "Front-end and API tests pass",
            "CI/CD, containers, deployment, and release documentation are complete"
          ],
          "tasks": [
            {"title":"DayVector v0.1 — Authentication, profiles, and tasks","minutes":1200,"mode":"pomodoro","resource_name":"Full Stack Open Parts 3–4","url":"https://fullstackopen.com/en/part3"},
            {"title":"DayVector v0.2 — Roadmaps and recurring tasks","minutes":1200,"mode":"pomodoro","resource_name":"React Managing State","url":"https://react.dev/learn/managing-state"},
            {"title":"DayVector v0.3 — Pomodoro and general time tracking","minutes":900,"mode":"pomodoro","resource_name":"Node.js Timers","url":"https://nodejs.org/api/timers.html"},
            {"title":"DayVector v0.4 — Notes, interruptions, and reminders","minutes":900,"mode":"pomodoro","resource_name":"MDN Notifications API","url":"https://developer.mozilla.org/en-US/docs/Web/API/Notifications_API"},
            {"title":"DayVector v0.5 — PostgreSQL database and reporting","minutes":1200,"mode":"pomodoro","resource_name":"PostgreSQL Tutorial","url":"https://www.postgresql.org/docs/current/tutorial.html"},
            {"title":"DayVector v0.6 — Automated front-end and API tests","minutes":900,"mode":"pomodoro","resource_name":"Full Stack Open Part 5","url":"https://fullstackopen.com/en/part5"},
            {"title":"DayVector v0.7 — Continuous integration","minutes":720,"mode":"pomodoro","resource_name":"Full Stack Open Part 11","url":"https://fullstackopen.com/en/part11"},
            {"title":"DayVector v0.8 — Containers and deployment","minutes":720,"mode":"pomodoro","resource_name":"Full Stack Open Part 12","url":"https://fullstackopen.com/en/part12"},
            {"title":"DayVector v1.0 — Stable portfolio release","minutes":720,"mode":"pomodoro","resource_name":"GitHub Releases documentation","url":"https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases"}
          ]
        },
        {
          "key": "p8",
          "title": "Phase 8 — Portfolio and Employment Preparation",
          "duration": "14–16 weeks",
          "days": 112,
          "milestone": "Job-ready full-stack portfolio and interview preparation completed",
          "checkpoints": [
            "Four strong portfolio projects are documented and deployed",
            "Every project has a useful README and release",
            "JavaScript, HTTP, React, Node.js, and PostgreSQL are reviewed",
            "Applications and technical interview preparation are active"
          ],
          "tasks": [
            {"title":"Polish DayVector as a portfolio project","minutes":1200,"mode":"pomodoro","resource_name":"GitHub README guidance","url":"https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes"},
            {"title":"Polish Y.D Glass Manager as a portfolio project","minutes":900,"mode":"pomodoro","resource_name":"GitHub README guidance","url":"https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes"},
            {"title":"Build an Accounting Management portfolio project","minutes":1200,"mode":"pomodoro","resource_name":"MDN Learn Web Development","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/"},
            {"title":"Build a public API application with caching, filtering, and pagination","minutes":900,"mode":"pomodoro","resource_name":"MDN Fetch API","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API"},
            {"title":"Complete freeCodeCamp’s final Full-Stack curriculum","minutes":2400,"mode":"pomodoro","resource_name":"freeCodeCamp Full-Stack Developer","url":"https://www.freecodecamp.org/learn/full-stack-developer-v9/"},
            {"title":"Improve every project README","minutes":480,"mode":"continuous","resource_name":"GitHub README guidance","url":"https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes"},
            {"title":"Create project releases","minutes":360,"mode":"checklist","resource_name":"GitHub Releases documentation","url":"https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases"},
            {"title":"Review JavaScript interview concepts","minutes":480,"mode":"continuous","resource_name":"MDN JavaScript Guide","url":"https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide"},
            {"title":"Review HTTP for interviews","minutes":300,"mode":"continuous","resource_name":"MDN HTTP","url":"https://developer.mozilla.org/en-US/docs/Web/HTTP"},
            {"title":"Review React for interviews","minutes":360,"mode":"continuous","resource_name":"React Learn","url":"https://react.dev/learn"},
            {"title":"Review Node.js for interviews","minutes":360,"mode":"continuous","resource_name":"Node.js Learn","url":"https://nodejs.org/en/learn"},
            {"title":"Review PostgreSQL for interviews","minutes":360,"mode":"continuous","resource_name":"PostgreSQL Tutorial","url":"https://www.postgresql.org/docs/current/tutorial.html"}
          ]
        }
      ]
    },
    {
      "key": "german_professional_fluency",
      "title": "German Professional Fluency",
      "description": "A sustainable German plan using Nicos Weg as the structured course, Duolingo for short daily vocabulary review, Goethe practice and exams, Easy German for authentic listening, Tandem for live speaking, and professional technical German practice.",
      "outcome": "Functional B1, professional B2, and advanced C1 German communication",
      "target_days": 1454,
      "required_effort_hours": 1300,
      "weekly_target_hours": "6–7",
      "target_summary": "Functional B1 in approximately 14–18 months, professional B2 in 24–30 months, and advanced C1 in 36–48 months",
      "study_cycle": ["structured course","vocabulary review","listening and shadowing","writing","live speaking","correction and repetition"],
      "initial_eight_week_focus": ["Take the Goethe test","Start Nicos Weg","Use Duolingo for 10 minutes daily","Record a one-minute self-introduction","Complete Goethe A1 exercises","Write about the working day","Complete a first Tandem exchange","Hold a five-to-ten-minute conversation"],
      "phases": [
        {
          "key": "g0",
          "title": "German Phase 0 — Placement and Pronunciation",
          "duration": "1–2 weeks",
          "days": 14,
          "milestone": "Starting German level and pronunciation baseline confirmed",
          "checkpoints": [
            "Approximate starting level is recorded",
            "One-minute self-introduction is recorded",
            "Initial A1 targets are documented"
          ],
          "tasks": [
            {"title":"Take the free Goethe quick test","minutes":60,"mode":"continuous","resource_name":"Goethe quick test","url":"https://www.goethe.de/en/spr/kur/tsd.html"},
            {"title":"Review the Arabic Goethe Cairo placement page","minutes":30,"mode":"continuous","resource_name":"Goethe Cairo placement","url":"https://www.goethe.de/ins/eg/ar/sta/kai/kur/tst.html"},
            {"title":"Start Nicos Weg","minutes":60,"mode":"continuous","resource_name":"DW Nicos Weg","url":"https://learngerman.dw.com/en/overview"},
            {"title":"Start Duolingo German","minutes":30,"mode":"habit","resource_name":"Duolingo German","url":"https://www.duolingo.com/course/de/en/Learn-German"},
            {"title":"Record a one-minute self-introduction","minutes":30,"mode":"continuous","resource_name":"Vocaroo","url":"https://vocaroo.com/"}
          ]
        },
        {
          "key": "g1",
          "title": "German Phase 1 — A1",
          "duration": "Months 1–4",
          "days": 120,
          "milestone": "A1 foundation completed",
          "checkpoints": [
            "Introduce yourself and your family",
            "Describe your job and daily routine",
            "Tell time and arrange appointments",
            "Handle food, shopping, and directions",
            "Use basic programming vocabulary",
            "Complete A1 exam practice"
          ],
          "tasks": [
            {"title":"Use Duolingo for 10 minutes Monday–Saturday","minutes":1200,"mode":"habit","resource_name":"Duolingo German","url":"https://www.duolingo.com/course/de/en/Learn-German"},
            {"title":"Complete four 30-minute Nicos Weg lessons weekly","minutes":2880,"mode":"continuous","resource_name":"DW Nicos Weg","url":"https://learngerman.dw.com/en/overview"},
            {"title":"Complete two Goethe A1 exercise sessions weekly","minutes":1440,"mode":"continuous","resource_name":"Goethe Deutsch für dich","url":"https://www.goethe.de/prj/dfd/en/home.cfm"},
            {"title":"Practise pronunciation and shadowing twice weekly","minutes":960,"mode":"continuous","resource_name":"DW Learn German YouTube","url":"https://www.youtube.com/@dwlearngerman"},
            {"title":"Write 60–80 German words every Friday","minutes":720,"mode":"continuous","resource_name":"Goethe German exercises","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Complete a five-minute speaking attempt every Friday","minutes":480,"mode":"continuous","resource_name":"Tandem","url":"https://tandem.net/"},
            {"title":"Complete the A1 practice exam","minutes":180,"mode":"checklist","resource_name":"Goethe A1 practice exam","url":"https://www.goethe.de/en/spr/prf/ueb/pa1.html"}
          ]
        },
        {
          "key": "g2",
          "title": "German Phase 2 — A2",
          "duration": "Months 5–9",
          "days": 150,
          "milestone": "A2 functional conversation reached",
          "checkpoints": [
            "Speak for ten minutes about familiar subjects",
            "Explain current programming studies simply",
            "Describe past and future activities",
            "Handle shopping, travel, appointments, and simple problems",
            "Understand slow, clearly spoken German"
          ],
          "tasks": [
            {"title":"Review Duolingo daily for no more than 10 minutes","minutes":1500,"mode":"habit","resource_name":"Duolingo German","url":"https://www.duolingo.com/course/de/en/Learn-German"},
            {"title":"Complete Nicos Weg A2 four times weekly","minutes":3600,"mode":"continuous","resource_name":"DW Nicos Weg","url":"https://learngerman.dw.com/en/overview"},
            {"title":"Complete Goethe A2 exercises twice weekly","minutes":1800,"mode":"continuous","resource_name":"Goethe Deutsch für dich","url":"https://www.goethe.de/prj/dfd/en/home.cfm"},
            {"title":"Watch Easy German beginner or intermediate videos twice weekly","minutes":1500,"mode":"continuous","resource_name":"Easy German","url":"https://www.easygerman.org/"},
            {"title":"Hold a weekly 30-minute Tandem conversation","minutes":900,"mode":"continuous","resource_name":"Tandem","url":"https://tandem.net/"},
            {"title":"Write two German texts of 80–120 words weekly","minutes":1800,"mode":"continuous","resource_name":"Goethe German exercises","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Complete Goethe A2 exam training","minutes":240,"mode":"checklist","resource_name":"Goethe exam training","url":"https://www.goethe.de/en/spr/prf/ueb.html"}
          ]
        },
        {
          "key": "g3",
          "title": "German Phase 3 — B1",
          "duration": "Months 10–16",
          "days": 210,
          "milestone": "B1 conversational independence reached",
          "checkpoints": [
            "Maintain a 15–20-minute conversation",
            "Explain a software project using uncomplicated German",
            "Describe problems and solutions",
            "Understand the main ideas of standard German",
            "Write structured messages and short reports"
          ],
          "tasks": [
            {"title":"Complete Nicos Weg B1 three times weekly","minutes":3780,"mode":"continuous","resource_name":"DW Nicos Weg","url":"https://learngerman.dw.com/en/overview"},
            {"title":"Complete Goethe B1 exercises twice weekly","minutes":2520,"mode":"continuous","resource_name":"Goethe Deutsch für dich","url":"https://www.goethe.de/prj/dfd/en/home.cfm"},
            {"title":"Use Easy German videos or podcast twice weekly","minutes":2520,"mode":"continuous","resource_name":"Easy German Podcast","url":"https://www.easygerman.org/podcast"},
            {"title":"Complete two 30-minute speaking sessions weekly","minutes":2520,"mode":"continuous","resource_name":"Tandem","url":"https://tandem.net/"},
            {"title":"Write 150–200 German words weekly","minutes":1260,"mode":"continuous","resource_name":"Goethe German exercises","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Explain a programming project in German every two weeks","minutes":1260,"mode":"continuous","resource_name":"German MDN","url":"https://developer.mozilla.org/de/"},
            {"title":"Complete Goethe B1 exam training","minutes":300,"mode":"checklist","resource_name":"Goethe exam training","url":"https://www.goethe.de/en/spr/prf/ueb.html"}
          ]
        },
        {
          "key": "g4",
          "title": "German Phase 4 — B2 Professional Conversation",
          "duration": "Months 17–28",
          "days": 360,
          "milestone": "B2 professional communication reached",
          "checkpoints": [
            "Maintain a 30–45-minute conversation",
            "Explain architecture, database, and interface decisions",
            "Participate in meetings",
            "Understand normal-speed conversation on familiar subjects",
            "Write professional emails and technical explanations",
            "Prepare for a German-language technical interview"
          ],
          "tasks": [
            {"title":"Complete Goethe B2 exercises twice weekly","minutes":4320,"mode":"continuous","resource_name":"Goethe Deutsch für dich","url":"https://www.goethe.de/prj/dfd/en/home.cfm"},
            {"title":"Use Easy German podcast or regular-speed video three times weekly","minutes":6480,"mode":"continuous","resource_name":"Easy German Podcast","url":"https://www.easygerman.org/podcast"},
            {"title":"Complete two 45-minute live conversations weekly","minutes":6480,"mode":"continuous","resource_name":"Tandem","url":"https://tandem.net/"},
            {"title":"Write 200–300 German words weekly","minutes":2160,"mode":"continuous","resource_name":"Goethe German exercises","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Present a programming subject in German every two weeks","minutes":2160,"mode":"continuous","resource_name":"German MDN","url":"https://developer.mozilla.org/de/"},
            {"title":"Read technical documentation in German weekly","minutes":2160,"mode":"continuous","resource_name":"German MDN","url":"https://developer.mozilla.org/de/"},
            {"title":"Complete Goethe B2 exam training","minutes":360,"mode":"checklist","resource_name":"Goethe exam training","url":"https://www.goethe.de/en/spr/prf/ueb.html"}
          ]
        },
        {
          "key": "g5",
          "title": "German Phase 5 — C1",
          "duration": "Months 29–48",
          "days": 600,
          "milestone": "C1 advanced professional fluency reached",
          "checkpoints": [
            "Work and participate in technical meetings in German",
            "Explain complex systems and trade-offs",
            "Conduct technical interviews",
            "Understand implicit meanings and detailed arguments",
            "Write precise professional documentation",
            "Speak without continually translating from Arabic or English"
          ],
          "tasks": [
            {"title":"Use native German podcasts or videos three times weekly","minutes":10800,"mode":"continuous","resource_name":"Easy German Podcast","url":"https://www.easygerman.org/podcast"},
            {"title":"Complete corrected professional speaking twice weekly","minutes":7200,"mode":"continuous","resource_name":"Tandem","url":"https://tandem.net/"},
            {"title":"Complete Goethe C1 exercises weekly","minutes":3600,"mode":"continuous","resource_name":"Goethe Deutsch für dich","url":"https://www.goethe.de/prj/dfd/en/home.cfm"},
            {"title":"Write 300–500 German words weekly","minutes":3600,"mode":"continuous","resource_name":"Goethe German exercises","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Read German technology articles and documentation weekly","minutes":3600,"mode":"continuous","resource_name":"German MDN","url":"https://developer.mozilla.org/de/"},
            {"title":"Deliver a 15-minute technical presentation in German monthly","minutes":1200,"mode":"continuous","resource_name":"OBS Studio","url":"https://obsproject.com/"},
            {"title":"Complete Goethe C1 exam training","minutes":420,"mode":"checklist","resource_name":"Goethe exam training","url":"https://www.goethe.de/en/spr/prf/ueb.html"}
          ]
        }
      ]
    }
  ]
  $plans$::jsonb;
  schedules constant jsonb := $schedules$
  [
    {"key":"german_structured_workdays","title":"German structured lesson","resource_name":"DW Nicos Weg","roadmap":"german_professional_fluency","phase":"g1","frequency":"weekly","weekdays":[1,2,3,6,7],"time":"06:30","minutes":30,"mode":"continuous","reminder":10,"url":"https://learngerman.dw.com/en/overview"},
    {"key":"german_thursday_review","title":"German review","resource_name":"Goethe German exercises","roadmap":"german_professional_fluency","phase":"g1","frequency":"weekly","weekdays":[4],"time":"06:30","minutes":30,"mode":"continuous","reminder":10,"url":"https://www.goethe.de/en/spr/ueb.html"},
    {"key":"programming_hsoub_sat_mon","title":"Hsoub Academy","resource_name":"Hsoub Front-End Development","roadmap":"full_stack_programming","phase":"p1","frequency":"weekly","weekdays":[1,6],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://academy.hsoub.com/learn/front-end-web-development/"},
    {"key":"programming_fcc_sun_tue","title":"freeCodeCamp JavaScript","resource_name":"freeCodeCamp JavaScript certification","roadmap":"full_stack_programming","phase":"p1","frequency":"weekly","weekdays":[2,7],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://www.freecodecamp.org/learn/javascript-v9/"},
    {"key":"programming_wednesday_project","title":"Independent programming project","resource_name":"GitHub new repository","roadmap":"full_stack_programming","phase":"p1","frequency":"weekly","weekdays":[3],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://github.com/new"},
    {"key":"german_thursday_listening_speaking","title":"German listening and speaking","resource_name":"Easy German","roadmap":"german_professional_fluency","phase":"g1","frequency":"weekly","weekdays":[4],"time":"19:30","minutes":90,"mode":"continuous","reminder":10,"url":"https://www.easygerman.org/","additional_resources":[{"name":"Tandem","url":"https://tandem.net/"}]},
    {"key":"german_daily_duolingo","title":"Duolingo — 10 minutes","resource_name":"Duolingo German","roadmap":"german_professional_fluency","phase":"g1","frequency":"daily","weekdays":[],"time":"13:00","minutes":10,"mode":"habit","reminder":5,"url":"https://www.duolingo.com/course/de/en/Learn-German"},
    {"key":"programming_friday_main_project","title":"Main programming project","resource_name":"GitHub learning-roadmap repository","roadmap":"full_stack_programming","phase":"p1","frequency":"weekly","weekdays":[5],"time":"08:00","minutes":120,"mode":"pomodoro","reminder":15,"url":"https://github.com/new"},
    {"key":"programming_friday_course_docs","title":"Course work, documentation, or debugging","resource_name":"MDN Learn Web Development","roadmap":"full_stack_programming","phase":"p1","frequency":"weekly","weekdays":[5],"time":"10:30","minutes":120,"mode":"pomodoro","reminder":10,"url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/","additional_resources":[{"name":"freeCodeCamp JavaScript certification","url":"https://www.freecodecamp.org/learn/javascript-v9/"},{"name":"Hsoub Front-End Development","url":"https://academy.hsoub.com/learn/front-end-web-development/"}]},
    {"key":"german_friday_structured_study","title":"German structured study","resource_name":"DW Nicos Weg","roadmap":"german_professional_fluency","phase":"g1","frequency":"weekly","weekdays":[5],"time":"16:00","minutes":75,"mode":"continuous","reminder":10,"url":"https://learngerman.dw.com/en/overview"},
    {"key":"german_friday_speaking","title":"German speaking practice","resource_name":"Tandem","roadmap":"german_professional_fluency","phase":"g1","frequency":"weekly","weekdays":[5],"time":"18:00","minutes":45,"mode":"continuous","reminder":10,"url":"https://tandem.net/"}
  ]
  $schedules$::jsonb;
  roadmap_plan jsonb;
  phase_plan jsonb;
  task_plan jsonb;
  schedule_plan jsonb;
  additional_resource jsonb;
  checkpoint_title text;
  roadmap_id uuid;
  phase_id uuid;
  milestone_id uuid;
  checkpoint_id uuid;
  task_id uuid;
  template_id uuid;
  rule_id uuid;
  resource_id uuid;
  reminder_id uuid;
  roadmap_link_id uuid;
  phase_start date;
  phase_finish date;
  task_date date;
  first_date date;
  planned_start_at timestamptz;
  planned_end_at timestamptz;
  phase_index integer;
  task_index integer;
  task_count integer;
  checkpoint_index integer;
  duration_days integer;
  duration_minutes integer;
  reminder_minutes integer;
  weekday_values integer[];
  roadmap_key text;
  phase_key text;
  task_key text;
  schedule_key text;
  resource_key text;
begin
  if not exists (
    select 1
    from auth.users account
    where account.id = owner_id
  ) then
    raise exception
      'Configured DayVector owner UUID % does not exist',
      owner_id;
  end if;

  for roadmap_plan in
    select value
    from jsonb_array_elements(plans)
  loop
    roadmap_key := roadmap_plan ->> 'key';

    select roadmap.id
    into roadmap_id
    from public.roadmaps roadmap
    where roadmap.user_id = owner_id
      and roadmap.data ->> 'v0027_seed_key' = roadmap_key
    order by roadmap.created_at
    limit 1;

    if roadmap_id is null then
      roadmap_id := gen_random_uuid();
      insert into public.roadmaps (
        id, user_id, title, description, status, planned_start,
        original_target_date, forecast_target_date, final_outcome,
        required_effort_ms, data
      ) values (
        roadmap_id,
        owner_id,
        roadmap_plan ->> 'title',
        roadmap_plan ->> 'description',
        'active',
        plan_start,
        plan_start + ((roadmap_plan ->> 'target_days')::integer - 1),
        plan_start + ((roadmap_plan ->> 'target_days')::integer - 1),
        roadmap_plan ->> 'outcome',
        (roadmap_plan ->> 'required_effort_hours')::bigint * 3600000,
        jsonb_build_object(
          'v0027_seed_key', roadmap_key,
          'installed_release', installed_release,
          'umbrella_title', umbrella_title,
          'combined_weekly_target_hours', '17–19',
          'weekly_target_hours', roadmap_plan ->> 'weekly_target_hours',
          'target_summary', roadmap_plan ->> 'target_summary',
          'study_cycle', roadmap_plan -> 'study_cycle',
          'initial_eight_week_focus',
            roadmap_plan -> 'initial_eight_week_focus',
          'full_stack_open_cost',
            roadmap_plan ->> 'full_stack_open_cost',
          'owner_uuid_bound', true,
          'source', 'owner_learning_plan'
        )
      );
    else
      update public.roadmaps roadmap
      set
        title = roadmap_plan ->> 'title',
        description = roadmap_plan ->> 'description',
        planned_start = plan_start,
        original_target_date =
          plan_start + ((roadmap_plan ->> 'target_days')::integer - 1),
        forecast_target_date =
          plan_start + ((roadmap_plan ->> 'target_days')::integer - 1),
        final_outcome = roadmap_plan ->> 'outcome',
        required_effort_ms =
          (roadmap_plan ->> 'required_effort_hours')::bigint * 3600000,
        deleted_at = null,
        data = coalesce(roadmap.data, '{}'::jsonb) || jsonb_build_object(
          'v0027_seed_key', roadmap_key,
          'installed_release', installed_release,
          'umbrella_title', umbrella_title,
          'combined_weekly_target_hours', '17–19',
          'weekly_target_hours', roadmap_plan ->> 'weekly_target_hours',
          'target_summary', roadmap_plan ->> 'target_summary',
          'study_cycle', roadmap_plan -> 'study_cycle',
          'initial_eight_week_focus',
            roadmap_plan -> 'initial_eight_week_focus',
          'full_stack_open_cost',
            roadmap_plan ->> 'full_stack_open_cost',
          'owner_uuid_bound', true,
          'source', 'owner_learning_plan'
        ),
        updated_at = now()
      where roadmap.user_id = owner_id
        and roadmap.id = roadmap_id;
    end if;

    for checkpoint_title in
      select value
      from jsonb_array_elements_text(
        '["active_work_seconds","practice_seconds","reading_time","research_time"]'::jsonb
      )
    loop
      if not exists (
        select 1
        from public.roadmap_progress_rules rule_row
        where rule_row.user_id = owner_id
          and rule_row.roadmap_id = roadmap_id
          and rule_row.contribution_type = checkpoint_title
          and rule_row.deleted_at is null
      ) then
        insert into public.roadmap_progress_rules (
          id, user_id, roadmap_id, roadmap_phase_id, contribution_type,
          weight, automatic_credit_allowed, rule_config, data
        ) values (
          gen_random_uuid(),
          owner_id,
          roadmap_id,
          null,
          checkpoint_title,
          1,
          false,
          jsonb_build_object(
            'requires_approved_attribution', true,
            'source', 'owner_learning_plan'
          ),
          jsonb_build_object(
            'v0027_seed_key', roadmap_key || '/progress/' || checkpoint_title,
            'installed_release', installed_release
          )
        );
      end if;
    end loop;

    phase_start := plan_start;
    phase_index := 0;
    for phase_plan in
      select value
      from jsonb_array_elements(roadmap_plan -> 'phases')
    loop
      phase_key := roadmap_key || '/' || (phase_plan ->> 'key');
      duration_days := (phase_plan ->> 'days')::integer;
      phase_finish := phase_start + duration_days - 1;

      select phase.id
      into phase_id
      from public.roadmap_phases phase
      where phase.user_id = owner_id
        and phase.data ->> 'v0027_seed_key' = phase_key
      order by phase.created_at
      limit 1;

      if phase_id is null then
        phase_id := gen_random_uuid();
        insert into public.roadmap_phases (
          id, user_id, roadmap_id, title, description, position,
          planned_start, planned_finish, forecast_finish,
          required_effort_ms, status, risk_level, completion_rules, data
        ) values (
          phase_id,
          owner_id,
          roadmap_id,
          phase_plan ->> 'title',
          'Duration: ' || (phase_plan ->> 'duration'),
          phase_index,
          phase_start,
          phase_finish,
          phase_finish,
          null,
          'planned',
          'low',
          '["all_required_tasks","all_required_checkpoints"]'::jsonb,
          jsonb_build_object(
            'v0027_seed_key', phase_key,
            'duration_label', phase_plan ->> 'duration',
            'duration_days', duration_days,
            'installed_release', installed_release
          )
        );
      else
        update public.roadmap_phases phase
        set
          roadmap_id = roadmap_id,
          title = phase_plan ->> 'title',
          description = 'Duration: ' || (phase_plan ->> 'duration'),
          position = phase_index,
          planned_start = phase_start,
          planned_finish = phase_finish,
          forecast_finish = phase_finish,
          deleted_at = null,
          data = coalesce(phase.data, '{}'::jsonb) || jsonb_build_object(
            'v0027_seed_key', phase_key,
            'duration_label', phase_plan ->> 'duration',
            'duration_days', duration_days,
            'installed_release', installed_release
          ),
          updated_at = now()
        where phase.user_id = owner_id
          and phase.id = phase_id;
      end if;

      select milestone.id
      into milestone_id
      from public.roadmap_milestones milestone
      where milestone.user_id = owner_id
        and milestone.data ->> 'v0027_seed_key' = phase_key || '/milestone'
      order by milestone.created_at
      limit 1;

      if milestone_id is null then
        milestone_id := gen_random_uuid();
        insert into public.roadmap_milestones (
          id, user_id, roadmap_id, phase_id, title, description,
          target_date, position, weight, status, data
        ) values (
          milestone_id,
          owner_id,
          roadmap_id,
          phase_id,
          phase_plan ->> 'milestone',
          'Review the phase tasks and checkpoints before completion.',
          phase_finish,
          phase_index,
          1,
          'not_started',
          jsonb_build_object(
            'v0027_seed_key', phase_key || '/milestone',
            'completion_rule', 'all_required_tasks',
            'installed_release', installed_release
          )
        );
      else
        update public.roadmap_milestones milestone
        set
          roadmap_id = roadmap_id,
          phase_id = phase_id,
          title = phase_plan ->> 'milestone',
          target_date = phase_finish,
          position = phase_index,
          deleted_at = null,
          data = coalesce(milestone.data, '{}'::jsonb) || jsonb_build_object(
            'v0027_seed_key', phase_key || '/milestone',
            'completion_rule', 'all_required_tasks',
            'installed_release', installed_release
          ),
          updated_at = now()
        where milestone.user_id = owner_id
          and milestone.id = milestone_id;
      end if;

      checkpoint_index := 0;
      checkpoint_id := null;
      for checkpoint_title in
        select value
        from jsonb_array_elements_text(phase_plan -> 'checkpoints')
      loop
        select checkpoint.id
        into checkpoint_id
        from public.roadmap_checkpoints checkpoint
        where checkpoint.user_id = owner_id
          and checkpoint.data ->> 'v0027_seed_key' =
            phase_key || '/checkpoint/' || checkpoint_index::text
        order by checkpoint.created_at
        limit 1;

        if checkpoint_id is null then
          checkpoint_id := gen_random_uuid();
          insert into public.roadmap_checkpoints (
            id, user_id, roadmap_id, phase_id, milestone_id, title,
            objective, target_date, estimated_effort_ms, status, weight,
            completion_criteria, evidence, data
          ) values (
            checkpoint_id,
            owner_id,
            roadmap_id,
            phase_id,
            milestone_id,
            checkpoint_title,
            checkpoint_title,
            phase_finish,
            3600000,
            'not_started',
            1,
            jsonb_build_array(checkpoint_title),
            '[]'::jsonb,
            jsonb_build_object(
              'v0027_seed_key',
              phase_key || '/checkpoint/' || checkpoint_index::text,
              'required', true,
              'completion_rule', 'user_review',
              'installed_release', installed_release
            )
          );
        else
          update public.roadmap_checkpoints checkpoint
          set
            roadmap_id = roadmap_id,
            phase_id = phase_id,
            milestone_id = milestone_id,
            title = checkpoint_title,
            objective = checkpoint_title,
            target_date = phase_finish,
            completion_criteria = jsonb_build_array(checkpoint_title),
            deleted_at = null,
            data = coalesce(checkpoint.data, '{}'::jsonb) ||
              jsonb_build_object(
                'v0027_seed_key',
                phase_key || '/checkpoint/' || checkpoint_index::text,
                'required', true,
                'completion_rule', 'user_review',
                'installed_release', installed_release
              ),
            updated_at = now()
          where checkpoint.user_id = owner_id
            and checkpoint.id = checkpoint_id;
        end if;

        checkpoint_index := checkpoint_index + 1;
      end loop;

      task_count := jsonb_array_length(phase_plan -> 'tasks');
      task_index := 0;
      for task_plan in
        select value
        from jsonb_array_elements(phase_plan -> 'tasks')
      loop
        task_key :=
          phase_key || '/task/' || lpad(task_index::text, 3, '0');
        duration_minutes := (task_plan ->> 'minutes')::integer;
        task_date := phase_start + case
          when task_count <= 1 then 0
          else floor(
            task_index::numeric * greatest(duration_days - 1, 0) /
            greatest(task_count - 1, 1)
          )::integer
        end;
        select task.id
        into task_id
        from public.task_occurrences task
        where task.user_id = owner_id
          and task.data ->> 'v0027_seed_key' = task_key
        order by task.created_at
        limit 1;

        if task_id is null then
          task_id := gen_random_uuid();
          insert into public.task_occurrences (
            id, user_id, title, description, status, priority,
            execution_mode, scheduled_date, planned_start, planned_end,
            due_at, estimated_duration_ms, roadmap_id, roadmap_phase_id,
            data
          ) values (
            task_id,
            owner_id,
            task_plan ->> 'title',
            'Executable roadmap task for ' || (phase_plan ->> 'title'),
            'scheduled',
            2,
            (task_plan ->> 'mode')::public.execution_mode,
            task_date,
            null,
            null,
            (task_date::timestamp + time '23:59')
              at time zone 'Africa/Cairo',
            duration_minutes::bigint * 60000,
            roadmap_id,
            phase_id,
            jsonb_build_object(
              'v0027_seed_key', task_key,
              'v0027_plan_task', true,
              'completion_method', case
                when task_plan ->> 'mode' = 'checklist' then 'checklist'
                else 'duration'
              end,
              'suggested_resource', task_plan ->> 'url',
              'resource_name', task_plan ->> 'resource_name',
              'time_zone', 'Africa/Cairo',
              'installed_release', installed_release
            )
          );
        else
          update public.task_occurrences task
          set
            title = task_plan ->> 'title',
            description =
              'Executable roadmap task for ' || (phase_plan ->> 'title'),
            priority = 2,
            execution_mode = (task_plan ->> 'mode')::public.execution_mode,
            scheduled_date = task_date,
            planned_start = null,
            planned_end = null,
            due_at = (task_date::timestamp + time '23:59')
              at time zone 'Africa/Cairo',
            estimated_duration_ms = duration_minutes::bigint * 60000,
            roadmap_id = roadmap_id,
            roadmap_phase_id = phase_id,
            deleted_at = null,
            data = coalesce(task.data, '{}'::jsonb) || jsonb_build_object(
              'v0027_seed_key', task_key,
              'v0027_plan_task', true,
              'completion_method', case
                when task_plan ->> 'mode' = 'checklist' then 'checklist'
                else 'duration'
              end,
              'suggested_resource', task_plan ->> 'url',
              'resource_name', task_plan ->> 'resource_name',
              'time_zone', 'Africa/Cairo',
              'installed_release', installed_release
            ),
            updated_at = now()
          where task.user_id = owner_id
            and task.id = task_id;
        end if;

        select task_link.id
        into roadmap_link_id
        from public.roadmap_task_links task_link
        where task_link.user_id = owner_id
          and task_link.data ->> 'v0027_seed_key' = task_key || '/link'
        order by task_link.created_at
        limit 1;

        if roadmap_link_id is null then
          roadmap_link_id := gen_random_uuid();
          insert into public.roadmap_task_links (
            id, user_id, roadmap_id, phase_id, milestone_id,
            checkpoint_id, task_id, relationship_type, contribution_rule,
            progress_weight, title, status, position, data
          ) values (
            roadmap_link_id,
            owner_id,
            roadmap_id,
            phase_id,
            milestone_id,
            null,
            task_id,
            'primary',
            'completion_only',
            1,
            'Task connection',
            'active',
            task_index,
            jsonb_build_object(
              'v0027_seed_key', task_key || '/link',
              'installed_release', installed_release
            )
          );
        else
          update public.roadmap_task_links task_link
          set
            roadmap_id = roadmap_id,
            phase_id = phase_id,
            milestone_id = milestone_id,
            task_id = task_id,
            position = task_index,
            status = 'active',
            deleted_at = null,
            data = coalesce(task_link.data, '{}'::jsonb) ||
              jsonb_build_object(
                'v0027_seed_key', task_key || '/link',
                'installed_release', installed_release
              ),
            updated_at = now()
          where task_link.user_id = owner_id
            and task_link.id = roadmap_link_id;
        end if;

        resource_key := task_key || '/resource/0';
        select resource.id
        into resource_id
        from public.task_resources resource
        where resource.user_id = owner_id
          and resource.data ->> 'v0027_seed_key' = resource_key
        order by resource.created_at
        limit 1;

        if resource_id is null then
          resource_id := gen_random_uuid();
          insert into public.task_resources (
            id, user_id, task_occurrence_id, roadmap_id, name,
            resource_type, description, storage_location, storage_path,
            privacy_state, data
          ) values (
            resource_id,
            owner_id,
            task_id,
            roadmap_id,
            task_plan ->> 'resource_name',
            'url',
            'Primary website resource for this roadmap task',
            'url',
            task_plan ->> 'url',
            'private',
            jsonb_build_object(
              'v0027_seed_key', resource_key,
              'open_mode', 'task_browser',
              'installed_release', installed_release
            )
          );
        else
          update public.task_resources resource
          set
            task_occurrence_id = task_id,
            roadmap_id = roadmap_id,
            name = task_plan ->> 'resource_name',
            resource_type = 'url',
            description = 'Primary website resource for this roadmap task',
            storage_location = 'url',
            storage_path = task_plan ->> 'url',
            privacy_state = 'private',
            deleted_at = null,
            data = coalesce(resource.data, '{}'::jsonb) ||
              jsonb_build_object(
                'v0027_seed_key', resource_key,
                'open_mode', 'task_browser',
                'installed_release', installed_release
              ),
            updated_at = now()
          where resource.user_id = owner_id
            and resource.id = resource_id;
        end if;

        task_index := task_index + 1;
      end loop;

      phase_start := phase_finish + 1;
      phase_index := phase_index + 1;
    end loop;
  end loop;

  for schedule_plan in
    select value
    from jsonb_array_elements(schedules)
  loop
    schedule_key := schedule_plan ->> 'key';

    select roadmap.id
    into roadmap_id
    from public.roadmaps roadmap
    where roadmap.user_id = owner_id
      and roadmap.data ->> 'v0027_seed_key' =
        schedule_plan ->> 'roadmap'
    order by roadmap.created_at
    limit 1;

    select phase.id
    into phase_id
    from public.roadmap_phases phase
    where phase.user_id = owner_id
      and phase.roadmap_id = roadmap_id
      and phase.data ->> 'v0027_seed_key' =
        (schedule_plan ->> 'roadmap') || '/' || (schedule_plan ->> 'phase')
    order by phase.created_at
    limit 1;

    if roadmap_id is null or phase_id is null then
      raise exception
        'Missing roadmap hierarchy for v0.0.27 schedule %',
        schedule_key;
    end if;

    duration_minutes := (schedule_plan ->> 'minutes')::integer;
    reminder_minutes := (schedule_plan ->> 'reminder')::integer;
    select coalesce(array_agg(value::integer order by ordinality), '{}')
    into weekday_values
    from jsonb_array_elements_text(schedule_plan -> 'weekdays')
      with ordinality as weekday(value, ordinality);

    select template.id
    into template_id
    from public.task_templates template
    where template.user_id = owner_id
      and template.data ->> 'v0027_seed_key' = schedule_key
    order by template.created_at
    limit 1;

    if template_id is null then
      template_id := gen_random_uuid();
      insert into public.task_templates (
        id, user_id, title, description, priority, execution_mode,
        default_duration_ms, roadmap_id, roadmap_phase_id,
        reminder_defaults, execution_settings, progress_settings, data
      ) values (
        template_id,
        owner_id,
        schedule_plan ->> 'title',
        'Sustainable recurring study timetable for DayVector v0.0.27',
        2,
        (schedule_plan ->> 'mode')::public.execution_mode,
        duration_minutes::bigint * 60000,
        roadmap_id,
        phase_id,
        jsonb_build_array(
          jsonb_build_object(
            'reminder_type', 'scheduled_start',
            'offset_ms', reminder_minutes * 60000,
            'sound_key', 'selected',
            'enabled', true
          )
        ),
        jsonb_build_object(
          'completion_method', 'duration',
          'suggested_resource', schedule_plan ->> 'url',
          'time_zone', 'Africa/Cairo'
        ),
        '{"completion_method":"duration"}'::jsonb,
        jsonb_build_object(
          'v0027_seed_key', schedule_key,
          'resource_url', schedule_plan ->> 'url',
          'time_zone', 'Africa/Cairo',
          'installed_release', installed_release
        )
      );
    else
      update public.task_templates template
      set
        title = schedule_plan ->> 'title',
        description =
          'Sustainable recurring study timetable for DayVector v0.0.27',
        priority = 2,
        execution_mode =
          (schedule_plan ->> 'mode')::public.execution_mode,
        default_duration_ms = duration_minutes::bigint * 60000,
        roadmap_id = roadmap_id,
        roadmap_phase_id = phase_id,
        reminder_defaults = jsonb_build_array(
          jsonb_build_object(
            'reminder_type', 'scheduled_start',
            'offset_ms', reminder_minutes * 60000,
            'sound_key', 'selected',
            'enabled', true
          )
        ),
        execution_settings =
          coalesce(template.execution_settings, '{}'::jsonb) ||
          jsonb_build_object(
            'completion_method', 'duration',
            'suggested_resource', schedule_plan ->> 'url',
            'time_zone', 'Africa/Cairo'
          ),
        deleted_at = null,
        data = coalesce(template.data, '{}'::jsonb) || jsonb_build_object(
          'v0027_seed_key', schedule_key,
          'resource_url', schedule_plan ->> 'url',
          'time_zone', 'Africa/Cairo',
          'installed_release', installed_release
        ),
        updated_at = now()
      where template.user_id = owner_id
        and template.id = template_id;
    end if;

    select rule.id
    into rule_id
    from public.recurrence_rules rule
    where rule.user_id = owner_id
      and rule.data ->> 'v0027_seed_key' = schedule_key
    order by rule.created_at
    limit 1;

    if rule_id is null then
      rule_id := gen_random_uuid();
      insert into public.recurrence_rules (
        id, user_id, frequency, interval_value, weekdays, starts_on,
        ends_on, maximum_occurrences, rule_data, data
      ) values (
        rule_id,
        owner_id,
        schedule_plan ->> 'frequency',
        1,
        weekday_values,
        plan_start,
        null,
        null,
        jsonb_build_object(
          'template_id', template_id,
          'frequency', schedule_plan ->> 'frequency',
          'interval_value', 1,
          'weekdays', schedule_plan -> 'weekdays',
          'starts_on', plan_start,
          'local_time', schedule_plan ->> 'time',
          'time_zone', 'Africa/Cairo',
          'created_from_owner_timetable', true
        ),
        jsonb_build_object(
          'v0027_seed_key', schedule_key,
          'installed_release', installed_release
        )
      );
    else
      update public.recurrence_rules rule
      set
        frequency = schedule_plan ->> 'frequency',
        interval_value = 1,
        weekdays = weekday_values,
        starts_on = plan_start,
        rule_data = coalesce(rule.rule_data, '{}'::jsonb) ||
          jsonb_build_object(
            'template_id', template_id,
            'frequency', schedule_plan ->> 'frequency',
            'interval_value', 1,
            'weekdays', schedule_plan -> 'weekdays',
            'starts_on', plan_start,
            'local_time', schedule_plan ->> 'time',
            'time_zone', 'Africa/Cairo',
            'created_from_owner_timetable', true
          ),
        deleted_at = null,
        data = coalesce(rule.data, '{}'::jsonb) || jsonb_build_object(
          'v0027_seed_key', schedule_key,
          'installed_release', installed_release
        ),
        updated_at = now()
      where rule.user_id = owner_id
        and rule.id = rule_id;
    end if;

    update public.task_templates template
    set
      recurrence_rule_id = rule_id,
      updated_at = now()
    where template.user_id = owner_id
      and template.id = template_id
      and template.recurrence_rule_id is distinct from rule_id;

    first_date := plan_start;
    if schedule_plan ->> 'frequency' = 'weekly' then
      while not (
        extract(isodow from first_date)::integer = any(weekday_values)
      )
      loop
        first_date := first_date + 1;
      end loop;
    end if;

    planned_start_at :=
      (first_date::timestamp + (schedule_plan ->> 'time')::time)
      at time zone 'Africa/Cairo';
    planned_end_at := planned_start_at + make_interval(
      mins => duration_minutes
    );

    select task.id
    into task_id
    from public.task_occurrences task
    where task.user_id = owner_id
      and task.template_id = template_id
      and task.occurrence_key = to_char(first_date, 'YYYY-MM-DD')
    order by task.created_at
    limit 1;

    if task_id is null then
      task_id := gen_random_uuid();
      insert into public.task_occurrences (
        id, user_id, template_id, title, description, status, priority,
        execution_mode, scheduled_date, planned_start, planned_end, due_at,
        estimated_duration_ms, roadmap_id, roadmap_phase_id,
        occurrence_key, data
      ) values (
        task_id,
        owner_id,
        template_id,
        schedule_plan ->> 'title',
        'First occurrence of the sustainable v0.0.27 study timetable',
        'scheduled',
        2,
        (schedule_plan ->> 'mode')::public.execution_mode,
        first_date,
        planned_start_at,
        planned_end_at,
        planned_end_at,
        duration_minutes::bigint * 60000,
        roadmap_id,
        phase_id,
        to_char(first_date, 'YYYY-MM-DD'),
        jsonb_build_object(
          'v0027_seed_key', schedule_key || '/first-occurrence',
          'completion_method', 'duration',
          'suggested_resource', schedule_plan ->> 'url',
          'reminder_offset_minutes', reminder_minutes,
          'schedule_template_key', schedule_key,
          'time_zone', 'Africa/Cairo',
          'installed_release', installed_release
        )
      );
    else
      update public.task_occurrences task
      set
        title = schedule_plan ->> 'title',
        description =
          'First occurrence of the sustainable v0.0.27 study timetable',
        priority = 2,
        execution_mode =
          (schedule_plan ->> 'mode')::public.execution_mode,
        scheduled_date = first_date,
        planned_start = planned_start_at,
        planned_end = planned_end_at,
        due_at = planned_end_at,
        estimated_duration_ms = duration_minutes::bigint * 60000,
        roadmap_id = roadmap_id,
        roadmap_phase_id = phase_id,
        deleted_at = null,
        data = coalesce(task.data, '{}'::jsonb) || jsonb_build_object(
          'v0027_seed_key', schedule_key || '/first-occurrence',
          'completion_method', 'duration',
          'suggested_resource', schedule_plan ->> 'url',
          'reminder_offset_minutes', reminder_minutes,
          'schedule_template_key', schedule_key,
          'time_zone', 'Africa/Cairo',
          'installed_release', installed_release
        ),
        updated_at = now()
      where task.user_id = owner_id
        and task.id = task_id;
    end if;

    select milestone.id
    into milestone_id
    from public.roadmap_milestones milestone
    where milestone.user_id = owner_id
      and milestone.roadmap_id = roadmap_id
      and milestone.phase_id = phase_id
      and milestone.deleted_at is null
    order by milestone.position, milestone.created_at
    limit 1;

    select task_link.id
    into roadmap_link_id
    from public.roadmap_task_links task_link
    where task_link.user_id = owner_id
      and task_link.data ->> 'v0027_seed_key' =
        schedule_key || '/first-occurrence/link'
    order by task_link.created_at
    limit 1;

    if roadmap_link_id is null then
      insert into public.roadmap_task_links (
        id, user_id, roadmap_id, phase_id, milestone_id, checkpoint_id,
        task_id, relationship_type, contribution_rule, progress_weight,
        title, status, data
      ) values (
        gen_random_uuid(),
        owner_id,
        roadmap_id,
        phase_id,
        milestone_id,
        null,
        task_id,
        'primary',
        'completion_only',
        1,
        'Recurring timetable connection',
        'active',
        jsonb_build_object(
          'v0027_seed_key', schedule_key || '/first-occurrence/link',
          'schedule_template_key', schedule_key,
          'installed_release', installed_release
        )
      );
    else
      update public.roadmap_task_links task_link
      set
        roadmap_id = roadmap_id,
        phase_id = phase_id,
        milestone_id = milestone_id,
        task_id = task_id,
        status = 'active',
        deleted_at = null,
        data = coalesce(task_link.data, '{}'::jsonb) ||
          jsonb_build_object(
            'v0027_seed_key', schedule_key || '/first-occurrence/link',
            'schedule_template_key', schedule_key,
            'installed_release', installed_release
          ),
        updated_at = now()
      where task_link.user_id = owner_id
        and task_link.id = roadmap_link_id;
    end if;

    resource_key := schedule_key || '/resource/0';
    select resource.id
    into resource_id
    from public.task_resources resource
    where resource.user_id = owner_id
      and resource.data ->> 'v0027_seed_key' = resource_key
    order by resource.created_at
    limit 1;

    if resource_id is null then
      insert into public.task_resources (
        id, user_id, task_occurrence_id, task_template_id, roadmap_id,
        name, resource_type, description, storage_location, storage_path,
        privacy_state, data
      ) values (
        gen_random_uuid(),
        owner_id,
        task_id,
        template_id,
        roadmap_id,
        schedule_plan ->> 'resource_name',
        'url',
        'Primary website resource for this recurring study session',
        'url',
        schedule_plan ->> 'url',
        'private',
        jsonb_build_object(
          'v0027_seed_key', resource_key,
          'schedule_template_key', schedule_key,
          'open_mode', 'task_browser',
          'installed_release', installed_release
        )
      );
    else
      update public.task_resources resource
      set
        task_occurrence_id = task_id,
        task_template_id = template_id,
        roadmap_id = roadmap_id,
        name = schedule_plan ->> 'resource_name',
        resource_type = 'url',
        description =
          'Primary website resource for this recurring study session',
        storage_location = 'url',
        storage_path = schedule_plan ->> 'url',
        privacy_state = 'private',
        deleted_at = null,
        data = coalesce(resource.data, '{}'::jsonb) ||
          jsonb_build_object(
            'v0027_seed_key', resource_key,
            'schedule_template_key', schedule_key,
            'open_mode', 'task_browser',
            'installed_release', installed_release
          ),
        updated_at = now()
      where resource.user_id = owner_id
        and resource.id = resource_id;
    end if;

    checkpoint_index := 1;
    for additional_resource in
      select value
      from jsonb_array_elements(
        coalesce(schedule_plan -> 'additional_resources', '[]'::jsonb)
      )
    loop
      resource_key :=
        schedule_key || '/resource/' || checkpoint_index::text;
      select resource.id
      into resource_id
      from public.task_resources resource
      where resource.user_id = owner_id
        and resource.data ->> 'v0027_seed_key' = resource_key
      order by resource.created_at
      limit 1;

      if resource_id is null then
        insert into public.task_resources (
          id, user_id, task_occurrence_id, task_template_id, roadmap_id,
          name, resource_type, description, storage_location, storage_path,
          privacy_state, data
        ) values (
          gen_random_uuid(),
          owner_id,
          task_id,
          template_id,
          roadmap_id,
          additional_resource ->> 'name',
          'url',
          'Additional website resource for this recurring study session',
          'url',
          additional_resource ->> 'url',
          'private',
          jsonb_build_object(
            'v0027_seed_key', resource_key,
            'schedule_template_key', schedule_key,
            'open_mode', 'task_browser',
            'installed_release', installed_release
          )
        );
      else
        update public.task_resources resource
        set
          task_occurrence_id = task_id,
          task_template_id = template_id,
          roadmap_id = roadmap_id,
          name = additional_resource ->> 'name',
          resource_type = 'url',
          description =
            'Additional website resource for this recurring study session',
          storage_location = 'url',
          storage_path = additional_resource ->> 'url',
          privacy_state = 'private',
          deleted_at = null,
          data = coalesce(resource.data, '{}'::jsonb) ||
            jsonb_build_object(
              'v0027_seed_key', resource_key,
              'schedule_template_key', schedule_key,
              'open_mode', 'task_browser',
              'installed_release', installed_release
            ),
          updated_at = now()
        where resource.user_id = owner_id
          and resource.id = resource_id;
      end if;

      checkpoint_index := checkpoint_index + 1;
    end loop;

    select reminder.id
    into reminder_id
    from public.task_reminders reminder
    where reminder.user_id = owner_id
      and reminder.data ->> 'v0027_seed_key' = schedule_key || '/reminder'
    order by reminder.created_at
    limit 1;

    if reminder_id is null then
      insert into public.task_reminders (
        id, user_id, task_template_id, task_occurrence_id, reminder_type,
        scheduled_at, offset_ms, repeat_rule, sound_key, enabled, data
      ) values (
        gen_random_uuid(),
        owner_id,
        template_id,
        task_id,
        'scheduled_start',
        planned_start_at - make_interval(mins => reminder_minutes),
        reminder_minutes * 60000,
        jsonb_build_object(
          'frequency', schedule_plan ->> 'frequency',
          'weekdays', schedule_plan -> 'weekdays',
          'time_zone', 'Africa/Cairo'
        ),
        'selected',
        true,
        jsonb_build_object(
          'v0027_seed_key', schedule_key || '/reminder',
          'schedule_template_key', schedule_key,
          'installed_release', installed_release
        )
      );
    else
      update public.task_reminders reminder
      set
        task_template_id = template_id,
        task_occurrence_id = task_id,
        reminder_type = 'scheduled_start',
        scheduled_at =
          planned_start_at - make_interval(mins => reminder_minutes),
        offset_ms = reminder_minutes * 60000,
        repeat_rule = jsonb_build_object(
          'frequency', schedule_plan ->> 'frequency',
          'weekdays', schedule_plan -> 'weekdays',
          'time_zone', 'Africa/Cairo'
        ),
        sound_key = 'selected',
        deleted_at = null,
        data = coalesce(reminder.data, '{}'::jsonb) ||
          jsonb_build_object(
            'v0027_seed_key', schedule_key || '/reminder',
            'schedule_template_key', schedule_key,
            'installed_release', installed_release
          ),
        updated_at = now()
      where reminder.user_id = owner_id
        and reminder.id = reminder_id;
    end if;
  end loop;
end
$seed$;
