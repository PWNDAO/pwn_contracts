const STYLE = {
	basic: "\x1b[36m",
	highlighted: "\x1b[32m",
	reset: "\x1b[0m",
};

function log(text, style = STYLE.basic) {
    console.log(style, text, STYLE.reset);
}

module.exports = { STYLE, log };
