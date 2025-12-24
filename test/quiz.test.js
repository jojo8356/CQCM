import puppeteer from 'puppeteer';

const BASE_URL = 'http://localhost:4321';

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('🚀 Starting Puppeteer tests...\n');

  const browser = await puppeteer.launch({
    headless: false,
    slowMo: 30,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  let passed = 0;
  let failed = 0;

  const test = async (name, fn) => {
    try {
      await fn();
      console.log(`✅ ${name}`);
      passed++;
    } catch (error) {
      console.log(`❌ ${name}`);
      console.log(`   Error: ${error.message}`);
      failed++;
    }
  };

  // Test 1: Page loads
  await test('Page loads correctly', async () => {
    await page.goto(BASE_URL, { waitUntil: 'networkidle0' });
    const title = await page.title();
    if (!title.includes('QCM')) throw new Error(`Expected title to contain 'QCM', got '${title}'`);
  });

  // Test 2: Load question 115 directly via URL
  await test('Question 115 loads via URL filter', async () => {
    await page.goto(`${BASE_URL}?q=115`, { waitUntil: 'networkidle0' });
    await delay(500);

    // Check question 115 is displayed
    const questionExists = await page.$('#question-115');
    if (!questionExists) throw new Error('Question 115 not found');

    const questionText = await page.$eval('#question-115 h3', el => el.textContent);
    if (!questionText.includes('115')) throw new Error('Question 115 number not displayed');
    if (!questionText.includes('2 réponses')) throw new Error('Badge "2 réponses" not found');
    console.log('   Question 115 loaded with "2 réponses" badge ✓');
  });

  // Test 3: Multiple answer selection - CORRECT answers
  await test('Selecting correct multiple answers validates as correct', async () => {
    // Reload to reset state
    await page.goto(`${BASE_URL}?q=115`, { waitUntil: 'networkidle0' });
    await delay(300);

    // Get all option buttons in question 115
    const buttons = await page.$$('#question-115 .space-y-2 button');
    console.log(`   Found ${buttons.length} option buttons`);

    if (buttons.length !== 6) {
      throw new Error(`Expected 6 buttons, found ${buttons.length}`);
    }

    // Question 115 has correctIndex [3, 4]
    // Click 4th option (index 3)
    await buttons[3].click();
    await delay(300);

    // Check first selection has blue border
    const firstClass = await buttons[3].evaluate(el => el.className);
    console.log(`   After 1st click, button 3 class includes 'blue': ${firstClass.includes('blue')}`);
    if (!firstClass.includes('blue')) {
      throw new Error(`Expected blue border after first click. Got: ${firstClass}`);
    }

    // Click 5th option (index 4) - should auto-validate
    await buttons[4].click();
    await delay(500);

    // Check both are now green (correct answers)
    const btn3Class = await buttons[3].evaluate(el => el.className);
    const btn4Class = await buttons[4].evaluate(el => el.className);

    console.log(`   Button 3 has green: ${btn3Class.includes('green')}`);
    console.log(`   Button 4 has green: ${btn4Class.includes('green')}`);

    if (!btn3Class.includes('green')) {
      throw new Error(`Button 3 should be green. Class: ${btn3Class}`);
    }
    if (!btn4Class.includes('green')) {
      throw new Error(`Button 4 should be green. Class: ${btn4Class}`);
    }
  });

  // Test 4: Check correct message appears
  await test('Correct message appears after right answers', async () => {
    const questionHtml = await page.$eval('#question-115', el => el.innerHTML);
    if (!questionHtml.includes('Correct')) {
      throw new Error('Correct message not found in question');
    }
    console.log('   "Correct" message found ✓');
  });

  // Test 5: Question card has green border
  await test('Question card has green border when correct', async () => {
    const cardClass = await page.$eval('#question-115', el => el.className);
    if (!cardClass.includes('border-green')) {
      throw new Error(`Expected green border on card. Class: ${cardClass}`);
    }
    console.log('   Card has green border ✓');
  });

  // Test 6: Test WRONG multiple answers
  await test('Selecting wrong multiple answers shows incorrect', async () => {
    // Navigate with filter in URL to reset
    await page.goto(`${BASE_URL}?q=115`, { waitUntil: 'networkidle0' });
    await delay(500);

    const buttons = await page.$$('#question-115 .space-y-2 button');

    // Click wrong answers (index 0 and 1)
    await buttons[0].click();
    await delay(200);
    await buttons[1].click();
    await delay(500);

    // Check question card has red border (incorrect)
    const questionClass = await page.$eval('#question-115', el => el.className);
    console.log(`   Question card has red border: ${questionClass.includes('red')}`);

    if (!questionClass.includes('red')) {
      throw new Error(`Expected red border on question card. Class: ${questionClass}`);
    }

    // Check selected wrong answers are red
    const btn0Class = await buttons[0].evaluate(el => el.className);
    const btn1Class = await buttons[1].evaluate(el => el.className);
    console.log(`   Button 0 (wrong, selected) has red: ${btn0Class.includes('red')}`);
    console.log(`   Button 1 (wrong, selected) has red: ${btn1Class.includes('red')}`);

    // Check correct answers are shown in green
    const btn3Class = await buttons[3].evaluate(el => el.className);
    const btn4Class = await buttons[4].evaluate(el => el.className);
    console.log(`   Button 3 (correct) has green: ${btn3Class.includes('green')}`);
    console.log(`   Button 4 (correct) has green: ${btn4Class.includes('green')}`);

    if (!btn3Class.includes('green')) {
      throw new Error('Correct answer (index 3) should be green');
    }
    if (!btn4Class.includes('green')) {
      throw new Error('Correct answer (index 4) should be green');
    }
  });

  // Test 7: Test single answer question
  await test('Single answer question works correctly', async () => {
    await page.goto(`${BASE_URL}?q=1`, { waitUntil: 'networkidle0' });
    await delay(500);

    const buttons = await page.$$('#question-1 .space-y-2 button');
    console.log(`   Found ${buttons.length} buttons for question 1`);

    // Question 1 has correctIndex 2 (3rd option)
    // Click correct answer
    await buttons[2].click();
    await delay(300);

    const btnClass = await buttons[2].evaluate(el => el.className);
    const cardClass = await page.$eval('#question-1', el => el.className);

    console.log(`   Correct button has green: ${btnClass.includes('green')}`);
    console.log(`   Card has green border: ${cardClass.includes('green')}`);

    if (!btnClass.includes('green')) {
      throw new Error('Correct button should be green');
    }
    if (!cardClass.includes('green')) {
      throw new Error('Card should have green border');
    }
  });

  // Test 8: Test single answer question with wrong answer
  await test('Single answer wrong shows incorrect', async () => {
    await page.goto(`${BASE_URL}?q=1`, { waitUntil: 'networkidle0' });
    await delay(500);

    const buttons = await page.$$('#question-1 .space-y-2 button');

    // Click wrong answer (index 0, correct is index 2)
    await buttons[0].click();
    await delay(300);

    const cardClass = await page.$eval('#question-1', el => el.className);
    const btn0Class = await buttons[0].evaluate(el => el.className);
    const btn2Class = await buttons[2].evaluate(el => el.className);

    console.log(`   Card has red border: ${cardClass.includes('red')}`);
    console.log(`   Wrong button has red: ${btn0Class.includes('red')}`);
    console.log(`   Correct button has green: ${btn2Class.includes('green')}`);

    if (!cardClass.includes('red')) {
      throw new Error('Card should have red border for wrong answer');
    }
    if (!btn0Class.includes('red')) {
      throw new Error('Selected wrong button should be red');
    }
    if (!btn2Class.includes('green')) {
      throw new Error('Correct button should be shown in green');
    }
  });

  // Summary
  console.log('\n' + '='.repeat(50));
  console.log(`Tests: ${passed} passed, ${failed} failed`);
  console.log('='.repeat(50));

  await browser.close();

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
